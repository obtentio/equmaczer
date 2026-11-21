// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import AppKit
import Combine
import Foundation
import os.log

/// Manages meter state and updates observers directly.
/// Uses Timer for meter updates at 30 FPS.
/// Updates are pushed directly to observers, bypassing SwiftUI's observation system.
@MainActor
final class MeterStore: ObservableObject {
    // MARK: - Observable Properties (for UI controls only)

    /// Programme loudness readings (BS.1770), updated while routing
    /// runs — independent of the level-meter timer, because the
    /// bypass-match gain must track even with the window closed.
    @Published private(set) var integratedLUFS: Double?
    @Published private(set) var shortTermLUFS: Double?
    /// The loudness-match gain currently applied to the flat-compare
    /// path, in dB. Nil while measuring or when the feature is off.
    @Published private(set) var bypassMatchDB: Double?

    /// Loudness computation over drained block energies.
    let loudnessMeter = LoudnessMeter()

    /// Whether loudness-matched bypass is enabled (wired by
    /// PipelineManager to the EQ configuration).
    var matchedBypassEnabledProvider: (() -> Bool)?

    /// Latest output spectrum bands in dBFS (48 log-spaced bands),
    /// refreshed on the meter tick while the spectrum display is on.
    @Published private(set) var spectrumBands: [Float] = []

    /// Peak true-peak limiter gain reduction per channel (dB, >= 0)
    /// over the last meter tick, for the Zone B limiter readout.
    @Published private(set) var limiterGainReductionDB: [Float] = [0, 0]

    /// Display-ready meter state for the lattice deck, refreshed on
    /// the same tick as the observer meters. The positions are the
    /// store's own ballistics-applied normalised values (the −36…0
    /// dB range through the meter gamma curve) — exactly what the
    /// bar meters drew. Ordered [input L, input R, output L,
    /// output R]. The readouts are the tick's raw peak dB.
    @Published private(set) var peakPositions: [Float] = [0, 0, 0, 0]
    @Published private(set) var peakHoldPositions: [Float] = [0, 0, 0, 0]
    @Published private(set) var rmsPositions: [Float] = [0, 0, 0, 0]
    @Published private(set) var peakReadoutsDB: [Float] = [-36, -36, -36, -36]

    /// Whether the spectrum display is enabled (wired by
    /// PipelineManager to the EQ configuration).
    var spectrumEnabledProvider: (() -> Bool)?

    /// Total auto-preamp cut currently in force (manual + correction
    /// layers), wired by PipelineManager to the EQ configuration.
    /// Watched across loudness ticks so a restage can shift the
    /// bypass delta by exactly the preamp change it caused.
    var preampSumProvider: (() -> Double)?

    private var lastRestageCount: UInt64?
    private var lastPreampSumDB: Double = 0

    private var loudnessTimer: AnyCancellable?

    /// Whether meters are enabled. Published for UI toggle synchronization only.
    @Published var metersEnabled: Bool = true {
        didSet {
            if !metersEnabled {
                // Reset all observers to silent state
                notifyAllObserversSilent()
                stopMeterUpdates()
            } else {
                startMeterUpdates()
            }
        }
    }
    
    // MARK: - Observer Management
    
    private var observers: [MeterType: [WeakMeterObserver]] = [:]
    private let observerQueue = DispatchQueue(label: "com.obtentio.equmaczer.meterObservers", qos: .userInteractive)
    
    // MARK: - Dependencies
    
    private weak var renderPipeline: RenderPipeline?
    private weak var equaliserWindow: NSWindow?
    private weak var popoverWindow: NSWindow?
    
    // MARK: - Timing
    
    private var meterTimer: AnyCancellable?
    private var activeMeterInterval: TimeInterval?
    private static let meterInterval: TimeInterval = 1.0 / 30.0  // 30 FPS
    
    // MARK: - State
    
    private var metersAtRest = false
    private var lastMeterValues: [MeterType: MeterValues] = [:]
    private let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "MeterStore")
    
    // MARK: - Value Storage
    
    private struct MeterValues {
        var peak: Float = 0
        var peakHold: Float = 0
        var peakHoldTimeRemaining: TimeInterval = 0
        var clipHold: TimeInterval = 0
        var rms: Float = 0
    }
    
    // MARK: - Initialization
    
    init(metersEnabled: Bool = true) {
        self.metersEnabled = metersEnabled
        for name in [NSWindow.didChangeOcclusionStateNotification,
                     NSWindow.didChangeScreenNotification,
                     NSWindow.willCloseNotification,
                     NSApplication.didBecomeActiveNotification,
                     NSApplication.didResignActiveNotification,
                     NSApplication.didHideNotification,
                     NSApplication.didUnhideNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(updateVisibility), name: name, object: nil)
        }
    }
    
    // MARK: - Observer Registration
    
    func addObserver(_ observer: MeterObserver, for type: MeterType) {
        observerQueue.sync {
            if observers[type] == nil {
                observers[type] = []
            }
            // Remove dead observers and check if already registered
            observers[type]?.removeAll { $0.observer == nil || $0.observer === observer }
            observers[type]?.append(WeakMeterObserver(observer: observer))
        }
        
        // Send initial silent state if meters disabled
        if !metersEnabled {
            observer.meterUpdated(value: 0, hold: 0, clipping: false)
        }
    }
    
    func removeObserver(_ observer: MeterObserver, for type: MeterType) {
        observerQueue.sync {
            observers[type]?.removeAll { $0.observer == nil || $0.observer === observer }
        }
    }
    
    func removeAllObservers(for observer: MeterObserver) {
        observerQueue.sync {
            for type in MeterType.allCases {
                observers[type]?.removeAll { $0.observer == nil || $0.observer === observer }
            }
        }
    }
    
    // MARK: - Lifecycle
    
    func setRenderPipeline(_ pipeline: RenderPipeline?) {
        self.renderPipeline = pipeline
        // Propagate initial meters enabled state to the pipeline
        pipeline?.setMetersEnabled(metersEnabled && displayVisible)

        // Loudness runs whenever a pipeline exists.
        loudnessMeter.reset()
        lastRestageCount = nil
        integratedLUFS = nil
        shortTermLUFS = nil
        bypassMatchDB = nil
        loudnessTimer?.cancel()
        loudnessTimer = nil
        if pipeline != nil {
            loudnessTimer = Timer.publish(every: 0.5, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.refreshLoudness()
                }
        }
        updateVisibility()
    }

    /// Drains loudness blocks, recomputes readings, and pushes the
    /// bypass-match gain implied by the current delta and setting.
    private func refreshLoudness() {
        guard let pipeline = renderPipeline else { return }

        // A restage since the last tick invalidates the paired
        // delta's history: reset it, seeded by the preamp change.
        let restageCount = pipeline.loudnessRestageCount
        let preampSum = preampSumProvider?() ?? 0
        if let lastRestageCount, restageCount != lastRestageCount {
            loudnessMeter.restage(
                preampDeltaDB: preampSum - lastPreampSumDB,
                absoluteSeedDB: preampSum
            )
        }
        lastRestageCount = restageCount
        lastPreampSumDB = preampSum

        let blocks = pipeline.drainLoudnessBlocks()
        loudnessMeter.ingest(display: blocks.display, pre: blocks.pre, post: blocks.post)
        if displayVisible {
            if integratedLUFS != loudnessMeter.integratedLUFS { integratedLUFS = loudnessMeter.integratedLUFS }
            if shortTermLUFS != loudnessMeter.shortTermLUFS { shortTermLUFS = loudnessMeter.shortTermLUFS }
        }

        let enabled = matchedBypassEnabledProvider?() ?? false
        if enabled, let delta = loudnessMeter.bypassDeltaDB {
            let matchDB = min(12.0, max(-12.0, -delta))
            if displayVisible, bypassMatchDB != matchDB { bypassMatchDB = matchDB }
            pipeline.setBypassMatchGain(linear: AudioMath.dbToLinear(Float(matchDB)))
        } else {
            if displayVisible, bypassMatchDB != nil { bypassMatchDB = nil }
            pipeline.setBypassMatchGain(linear: 1.0)
        }
    }
    
    // MARK: - Processing proof (B2)

    /// Measured facts for the proof of processing: the pipeline's
    /// own input/output RMS (dBFS, loudest channel) and the pre/post
    /// loudness delta. Refreshed on demand by
    /// `refreshProcessingProof()` — the meter tick sleeps when
    /// neither the main window nor the popover is visible, and the
    /// proof lives in the Settings window, so its pane drives this
    /// on its own timer while visible.
    @Published private(set) var proofInputRMSDB: Float = -90
    @Published private(set) var proofOutputRMSDB: Float = -90
    @Published private(set) var proofEffectLU: Double?

    func refreshProcessingProof() {
        guard let pipeline = renderPipeline else {
            proofInputRMSDB = -90
            proofOutputRMSDB = -90
            proofEffectLU = nil
            return
        }
        refreshLoudness()
        let meters = pipeline.currentMeters()
        proofInputRMSDB = meters.inputRmsDB.max() ?? -90
        proofOutputRMSDB = meters.outputRmsDB.max() ?? -90
        proofEffectLU = loudnessMeter.bypassDeltaDB
    }

    func setEqumaczerWindow(_ window: NSWindow?) {
        self.equaliserWindow = window
        updateVisibility()
    }

    private var mainWindowVisible: Bool {
        guard let window = equaliserWindow else { return false }
        // occlusion, not app focus: a visible window behind another app's keeps its spectrum live
        return window.isVisible && !window.isMiniaturized
            && window.occlusionState.contains(.visible)
    }

    private var displayVisible: Bool {
        NSApp?.isHidden == false && (mainWindowVisible || (popoverVisible && popoverWindow?.isVisible == true && popoverWindow?.occlusionState.contains(.visible) == true))
    }

    private var displayInterval: TimeInterval {
        let screen = mainWindowVisible ? equaliserWindow?.screen : popoverWindow?.screen
        return max(Self.meterInterval, 1.0 / Double(max(1, screen?.maximumFramesPerSecond ?? 30)))
    }

    @objc private func updateVisibility() {
        if meterTimer != nil, activeMeterInterval != displayInterval { stopMeterUpdates() }
        if displayVisible && metersEnabled && renderPipeline != nil { startMeterUpdates() }
        else if meterTimer != nil { stopMeterUpdates() }
    }

    func startMeterUpdates() {
        guard meterTimer == nil else { return }
        guard metersEnabled, displayVisible, renderPipeline != nil else { return }

        activeMeterInterval = displayInterval
        meterTimer = Timer.publish(every: displayInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshMeterSnapshot()
            }

        // Enable audio thread meter calculations
        renderPipeline?.setMetersEnabled(true)
    }

    func stopMeterUpdates() {
        meterTimer?.cancel()
        meterTimer = nil
        activeMeterInterval = nil
        metersAtRest = false
        notifyAllObserversSilent()

        // Disable audio thread meter calculations
        renderPipeline?.setMetersEnabled(false)
    }
    
    // MARK: - Window Lifecycle

    /// True while the menu-bar popover is on screen. The meter tick
    /// serves whichever surface is visible, so the popover's limiter
    /// cell stays live with the main window closed.
    private(set) var popoverVisible = false

    func windowBecameVisible() {
        updateVisibility()
    }

    func windowBecameHidden() {
        updateVisibility()
    }

    func setPopoverWindow(_ window: NSWindow?) {
        popoverWindow = window
        updateVisibility()
    }

    func popoverBecameVisible() {
        popoverVisible = true
        windowBecameVisible()
    }

    func popoverBecameHidden() {
        popoverVisible = false
        updateVisibility()
    }
    
    // MARK: - Update Cycle
    
    private func refreshMeterSnapshot() {
        guard metersEnabled else {
            notifyAllObserversSilent()
            return
        }

        guard displayVisible else { updateVisibility(); return }

        guard let pipeline = renderPipeline else { return }

        if mainWindowVisible, spectrumEnabledProvider?() ?? false {
            let bands = pipeline.spectrumBands()
            if bands != spectrumBands { spectrumBands = bands }
        }
        limiterGainReductionDB = pipeline.limiterGainReductionDB()

        let snapshot = pipeline.currentMeters()

        // Check if at rest (all meters silent)
        if metersAtRest {
            let stillSilent = snapshot.inputDB.allSatisfy({ $0 <= MeterConstants.silenceThreshold }) &&
                              snapshot.outputDB.allSatisfy({ $0 <= MeterConstants.silenceThreshold }) &&
                              snapshot.inputRmsDB.allSatisfy({ $0 <= MeterConstants.silenceThreshold }) &&
                              snapshot.outputRmsDB.allSatisfy({ $0 <= MeterConstants.silenceThreshold })

            if stillSilent {
                return
            }
            metersAtRest = false
        }

        // Batch all meter updates in a single CATransaction to reduce render server calls
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Process each meter type
        let interval = activeMeterInterval ?? MeterConstants.meterInterval
        
        // Input Peak - Left
        updateMeter(
            type: .inputPeakLeft,
            dbValue: snapshot.inputDB.indices.contains(0) ? snapshot.inputDB[0] : MeterConstants.meterRange.lowerBound,
            interval: interval
        )
        
        // Input Peak - Right
        updateMeter(
            type: .inputPeakRight,
            dbValue: snapshot.inputDB.indices.contains(1) ? snapshot.inputDB[1] : MeterConstants.meterRange.lowerBound,
            interval: interval
        )
        
        // Output Peak - Left
        updateMeter(
            type: .outputPeakLeft,
            dbValue: snapshot.outputDB.indices.contains(0) ? snapshot.outputDB[0] : MeterConstants.meterRange.lowerBound,
            interval: interval
        )
        
        // Output Peak - Right
        updateMeter(
            type: .outputPeakRight,
            dbValue: snapshot.outputDB.indices.contains(1) ? snapshot.outputDB[1] : MeterConstants.meterRange.lowerBound,
            interval: interval
        )
        
        // Input RMS - Left
        updateRMSMeter(
            type: .inputRMSLeft,
            dbValue: snapshot.inputRmsDB.indices.contains(0) ? snapshot.inputRmsDB[0] : MeterConstants.meterRange.lowerBound
        )
        
        // Input RMS - Right
        updateRMSMeter(
            type: .inputRMSRight,
            dbValue: snapshot.inputRmsDB.indices.contains(1) ? snapshot.inputRmsDB[1] : MeterConstants.meterRange.lowerBound
        )
        
        // Output RMS - Left
        updateRMSMeter(
            type: .outputRMSLeft,
            dbValue: snapshot.outputRmsDB.indices.contains(0) ? snapshot.outputRmsDB[0] : MeterConstants.meterRange.lowerBound
        )
        
        // Output RMS - Right
        updateRMSMeter(
            type: .outputRMSRight,
            dbValue: snapshot.outputRmsDB.indices.contains(1) ? snapshot.outputRmsDB[1] : MeterConstants.meterRange.lowerBound
        )
        
        // Check if we should go back to rest
        let inputPeakLeft = lastMeterValues[.inputPeakLeft]?.peak ?? Float(0)
        let inputPeakRight = lastMeterValues[.inputPeakRight]?.peak ?? Float(0)
        let outputPeakLeft = lastMeterValues[.outputPeakLeft]?.peak ?? Float(0)
        let outputPeakRight = lastMeterValues[.outputPeakRight]?.peak ?? Float(0)
        let inputRMSLeft = lastMeterValues[.inputRMSLeft]?.rms ?? Float(0)
        let inputRMSRight = lastMeterValues[.inputRMSRight]?.rms ?? Float(0)
        let outputRMSLeft = lastMeterValues[.outputRMSLeft]?.rms ?? Float(0)
        let outputRMSRight = lastMeterValues[.outputRMSRight]?.rms ?? Float(0)
        
        let allValues: [Float] = [
            inputPeakLeft, inputPeakRight, outputPeakLeft, outputPeakRight,
            inputRMSLeft, inputRMSRight, outputRMSLeft, outputRMSRight
        ]
        
        let inputHoldLeft = lastMeterValues[.inputPeakLeft]?.peakHold ?? Float(0)
        let inputHoldRight = lastMeterValues[.inputPeakRight]?.peakHold ?? Float(0)
        let outputHoldLeft = lastMeterValues[.outputPeakLeft]?.peakHold ?? Float(0)
        let outputHoldRight = lastMeterValues[.outputPeakRight]?.peakHold ?? Float(0)
        
        let allHolds: [Float] = [inputHoldLeft, inputHoldRight, outputHoldLeft, outputHoldRight]

        let allValuesSilent = allValues.allSatisfy({ $0 < MeterConstants.atRestThreshold })
        let allHoldsSilent = allHolds.allSatisfy({ $0 < MeterConstants.atRestThreshold })
        metersAtRest = allValuesSilent && allHoldsSilent

        // Publish the same ballistics-applied values for the
        // SwiftUI lattice deck, plus the tick's raw peak dB for
        // its numeric readouts.
        peakPositions = [inputPeakLeft, inputPeakRight, outputPeakLeft, outputPeakRight]
        peakHoldPositions = allHolds
        rmsPositions = [inputRMSLeft, inputRMSRight, outputRMSLeft, outputRMSRight]
        peakReadoutsDB = [
            snapshot.inputDB.indices.contains(0) ? snapshot.inputDB[0] : MeterConstants.meterRange.lowerBound,
            snapshot.inputDB.indices.contains(1) ? snapshot.inputDB[1] : MeterConstants.meterRange.lowerBound,
            snapshot.outputDB.indices.contains(0) ? snapshot.outputDB[0] : MeterConstants.meterRange.lowerBound,
            snapshot.outputDB.indices.contains(1) ? snapshot.outputDB[1] : MeterConstants.meterRange.lowerBound
        ]

        CATransaction.commit()
    }
    
    private func updateMeter(type: MeterType, dbValue: Float, interval: TimeInterval) {
        var values = lastMeterValues[type] ?? MeterValues()
        
        let normalized = MeterConstants.normalizedPosition(for: dbValue)
        let delta = normalized - values.peak
        let smoothing = delta >= 0 ? MeterConstants.peakAttackSmoothing : MeterConstants.peakReleaseSmoothing
        let rawPeak = values.peak + delta * smoothing
        let peak = max(0, min(1, rawPeak))
        
        let isClipping = dbValue >= 0
        let actualPeakForHold = isClipping ? normalized : peak
        let isNewPeak = actualPeakForHold > values.peakHold
        
        let newHoldTime: TimeInterval
        let peakHold: Float
        if isNewPeak {
            newHoldTime = MeterConstants.peakHoldDuration
            peakHold = actualPeakForHold
        } else if values.peakHoldTimeRemaining > 0 {
            newHoldTime = max(0, values.peakHoldTimeRemaining - interval)
            peakHold = values.peakHold
        } else {
            newHoldTime = 0
            let rawPeakHold = values.peakHold - MeterConstants.peakHoldDecayPerTick
            peakHold = max(0, min(1, rawPeakHold))
        }
        
        let clipHold = isClipping ? MeterConstants.clipHoldDuration : max(0, values.clipHold - interval)
        
        values.peak = peak
        values.peakHold = peakHold
        values.peakHoldTimeRemaining = newHoldTime
        values.clipHold = clipHold
        
        // Notify observers BEFORE storing new values so comparison uses old values
        notifyObservers(
            type: type,
            value: peak,
            hold: peakHold,
            clipping: clipHold > 0
        )
        
        lastMeterValues[type] = values
    }
    
    private func updateRMSMeter(type: MeterType, dbValue: Float) {
        var values = lastMeterValues[type] ?? MeterValues()
        
        let normalized = MeterConstants.normalizedPosition(for: dbValue)
        let delta = normalized - values.rms
        let rawRMS = values.rms + delta * MeterConstants.rmsSmoothing
        let rms = max(0, min(1, rawRMS))
        
        values.rms = rms
        
        // Notify observers BEFORE storing new values so comparison uses old values
        notifyObservers(type: type, value: rms, hold: 0, clipping: false)
        
        lastMeterValues[type] = values
    }
    
    private func notifyObservers(type: MeterType, value: Float, hold: Float, clipping: Bool) {
        // Check if value changed enough to notify
        if let last = lastMeterValues[type] {
            let lastTotal = last.peak + last.peakHold
            let newTotal = value + hold
            if abs(newTotal - lastTotal) < MeterConstants.changeThreshold && !clipping {
                return
            }
        }
        
        observerQueue.sync {
            guard let typeObservers = observers[type] else { return }
            
            for wrapper in typeObservers {
                wrapper.observer?.meterUpdated(value: value, hold: hold, clipping: clipping)
            }
        }
    }
    
    private func notifyAllObserversSilent() {
        observerQueue.sync {
            for type in MeterType.allCases {
                guard let typeObservers = observers[type] else { continue }
                for wrapper in typeObservers {
                    wrapper.observer?.meterUpdated(value: 0, hold: 0, clipping: false)
                }
            }
        }
        
        // Reset stored values
        lastMeterValues.removeAll()
    }
}
