// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
// EqumaczerStore.swift
// Thin coordinator for EQ application state

import Combine
import Foundation
import OSLog
import AppKit
import SwiftUI

@MainActor
final class EqumaczerStore: ObservableObject {
    let recordingController = RecordingController()
    let sceneEngine = SceneEngine()
    private let appVolumeStore: any AppVolumePersisting
    @Published private(set) var appVolumes: [String: Float] = [:]
    @Published private(set) var appVolumeNotice: String?

    func appVolume(for bundleID: String) -> Float { appVolumes[bundleID] ?? 1 }

    func updateAppVolume(bundleID: String, volume: Float) {
        guard volume.isFinite else { return }
        let value = min(max(volume, 0), 1)
        let active = channelController.playingBundleIDs.filter { appVolumes[$0] != nil }
        guard value == 1 || appVolumes[bundleID] != nil || active.count < ChannelMixer.maximumAppSlots else {
            appVolumeNotice = "Per-app volume is limited to \(ChannelMixer.maximumAppSlots) playing apps. Set one back to 100% to make room."
            return
        }
        appVolumeNotice = nil
        if value == 1 { appVolumes.removeValue(forKey: bundleID) }
        else { appVolumes[bundleID] = value }
        appVolumeStore.save(appVolumes)
        // Publish gain before membership changes; existing app taps never restart
        // for a slider drag. Topology changes use the coordinator's RouteSeam.
        routingCoordinator.pipelineManager.renderPipeline?.channelMixer?.appSlot(for: bundleID)?
            .volumeBits.store(value.bitPattern, ordering: .relaxed)
        channelController.refreshTapAssignments()
        let needsSwitch = manualModeEnabled || captureMode != .processTap || (routingCoordinator.currentCaptureMode ?? effectiveCaptureMode) != .processTap
        routingCoordinator.captureMode = .processTap
        if manualModeEnabled { manualModeEnabled = false }
        // A dead Process Tap would fall back again on every drag tick: keep the route, show the notice.
        if needsSwitch && routingStatus != .idle && !routingCoordinator.processTapFailed { routingCoordinator.reconfigureRouting() }
    }

    
    // MARK: - Computed Properties (delegate to EQConfiguration)
    
    /// Global bypass state - delegates to eqConfiguration.globalBypass.
    var isBypassed: Bool {
        get { eqConfiguration.globalBypass }
        set {
            eqConfiguration.globalBypass = newValue
            routingCoordinator.updateProcessingMode(systemEQOff: newValue, compareMode: compareMode)
        }
    }
    
    /// Band count - delegates to eqConfiguration.focusedChannelBandCount.
    /// In linked mode, returns the band count for both channels.
    /// In stereo mode, returns the band count for the currently focused channel.
    var bandCount: Int {
        get { eqConfiguration.focusedChannelBandCount }
        set {
            eqConfiguration.setActiveBandCount(newValue)

            // Only update pipeline if routing is active
            guard routingCoordinator.routingStatus.isActive else { return }

            // Reconfigure only if new band count exceeds current capacity
            if newValue > routingCoordinator.currentBandCapacity() {
                routingCoordinator.reconfigureRouting()
            } else {
                routingCoordinator.reapplyConfiguration()
            }
        }
    }
    
    /// Input gain (dB) - delegates to eqConfiguration.inputGain.
    /// The gain pushed to the pipeline is the effective gain (user gain
    /// plus auto-preamp attenuation), so boosts stay clip-free.
    var inputGain: Float {
        get { eqConfiguration.inputGain }
        set {
            let clamped = Self.clampGain(newValue)
        eqConfiguration.inputGain = clamped
        routingCoordinator.updateInputGain(linear: AudioMath.dbToLinear(eqConfiguration.effectiveInputGainDB))
        }
    }

    /// Auto-preamp toggle - delegates to eqConfiguration.autoPreampEnabled.
    var autoPreampEnabled: Bool {
        get { eqConfiguration.autoPreampEnabled }
        set {
            eqConfiguration.autoPreampEnabled = newValue
            routingCoordinator.updateInputGain(linear: AudioMath.dbToLinear(eqConfiguration.effectiveInputGainDB))
        }
    }

    /// Loudness compensation toggle - delegates to
    /// eqConfiguration.loudnessEnabled; the correction controller
    /// recomposes its layer when it changes.
    var loudnessEnabled: Bool {
        get { eqConfiguration.loudnessEnabled }
        set {
            eqConfiguration.loudnessEnabled = newValue
            correctionController.refresh()
        }
    }

    /// Loudness compensation strength (0...1).
    var loudnessStrength: Float {
        get { eqConfiguration.loudnessStrength }
        set {
            eqConfiguration.loudnessStrength = min(max(newValue, 0), 1)
            correctionController.refresh()
        }
    }

    /// Whether the flat-compare path is loudness-matched to the EQ path.
    var loudnessMatchedBypassEnabled: Bool {
        eqConfiguration.loudnessMatchedBypassEnabled
    }

    /// Whether the live output spectrum shows behind the band stage.
    var spectrumEnabled: Bool {
        get { eqConfiguration.spectrumEnabled }
        set { eqConfiguration.spectrumEnabled = newValue }
    }
    
    /// Output gain (dB) - delegates to eqConfiguration.outputGain.
    var outputGain: Float {
        get { eqConfiguration.outputGain }
        set {
            let clamped = Self.clampGain(newValue)
        eqConfiguration.outputGain = clamped
        routingCoordinator.updateOutputGain(linear: AudioMath.dbToLinear(clamped))
        }
    }
    
    // MARK: - Published Properties
    
    @Published var compareMode: CompareMode = .eq {
        didSet {
            routingCoordinator.updateProcessingMode(systemEQOff: isBypassed, compareMode: compareMode)
            
            if compareMode == .flat {
                compareModeTimer.start()
            } else {
                compareModeTimer.cancel()
            }
        }
    }
    
    /// User preference for displaying bandwidth as octaves or Q factor.
    @Published var bandwidthDisplayMode: BandwidthDisplayMode = .qFactor

    // MARK: - Forwarded Properties from RoutingCoordinator
    
    var routingStatus: RoutingStatus { routingCoordinator.routingStatus }

    /// Capture liveness fallback notice, shown in the status bar.
    var captureFallbackNotice: String? { routingCoordinator.captureFallbackNotice }
    
    var selectedInputDeviceID: String? {
        get { routingCoordinator.selectedInputDeviceID }
        set {
            let changed = routingCoordinator.selectedInputDeviceID != newValue
            routingCoordinator.selectedInputDeviceID = newValue
            if changed, let uid = newValue {
                activityJournal.record(.route, "Input set to \(deviceName(forUID: uid))")
            }
            if newValue != nil && routingCoordinator.selectedOutputDeviceID != nil {
                routingCoordinator.reconfigureRouting()
            }
        }
    }
    
    var selectedOutputDeviceID: String? {
        get { routingCoordinator.selectedOutputDeviceID }
        set {
            let changed = routingCoordinator.selectedOutputDeviceID != newValue
            routingCoordinator.selectedOutputDeviceID = newValue
            if changed, let uid = newValue {
                activityJournal.record(.route, "Output set to \(deviceName(forUID: uid))")
            }
            if routingCoordinator.selectedInputDeviceID != nil && newValue != nil {
                routingCoordinator.reconfigureRouting()
            }
        }
    }
    
    var manualModeEnabled: Bool {
        get { routingCoordinator.manualModeEnabled }
        set { routingCoordinator.manualModeEnabled = newValue }
    }

    /// Capture mode preference for automatic routing.
    /// Only applies when using the equmaczer driver in automatic mode.
    /// Manual mode always uses HAL input capture.
    var captureMode: CaptureMode {
        get { routingCoordinator.captureMode }
        set {
            let changed = routingCoordinator.captureMode != newValue
            routingCoordinator.captureMode = newValue
            if changed { activityJournal.record(.route, "Capture method set to \(newValue.displayName)") }
            // Reconfigure routing in automatic mode if not idle
            // This covers: active, starting, error states (e.g., permission denied then retry)
            if !routingCoordinator.manualModeEnabled && routingCoordinator.routingStatus != .idle {
                routingCoordinator.reconfigureRouting()
            }
        }
    }
    
    /// The capture mode currently in use (may differ from preference when driver doesn't support shared memory).
    /// Returns `halInput` when driver doesn't support shared memory or in fallback mode.
    var effectiveCaptureMode: CaptureMode {
        routingCoordinator.effectiveCaptureMode
    }

    /// Requests microphone permission and switches to HAL capture mode.
    /// Returns true if permission was granted, false otherwise.
    @MainActor
    func requestMicPermissionAndSwitchToHALCapture() async -> Bool {
        await routingCoordinator.requestMicPermissionAndSwitchToHALCapture()
    }

    var showDriverPrompt: Bool {
        get { routingCoordinator.showDriverPrompt }
        set { routingCoordinator.showDriverPrompt = newValue }
    }

    /// Whether the driver needs updating (missing shared memory support).
    var showDriverUpdateRequired: Bool {
        routingCoordinator.showDriverUpdateRequired
    }
    
    /// Clears the driver update required flag (after user visits Settings).
    func clearDriverUpdateRequired() {
        routingCoordinator.showDriverUpdateRequired = false
    }
    
    var inputDevices: [AudioDevice] { deviceManager.inputDevices }
    var outputDevices: [AudioDevice] { deviceManager.outputDevices }

    /// Enumerates input devices.
    /// May trigger TCC permission dialog for microphone access.
    /// Should be called after microphone permission is granted or when switching to manual mode.
    func enumerateInputDevices() {
        deviceManager.enumerateInputDevices()
    }

    // MARK: - Channel Mode

    /// Channel processing mode - delegates to eqConfiguration.
    var channelMode: ChannelMode {
        get { eqConfiguration.channelMode }
        set {
            eqConfiguration.setChannelMode(newValue)
            routingCoordinator.reapplyConfiguration()
            presetManager.markAsModified()
        }
    }

    /// Which channel is being edited in stereo mode.
    var channelFocus: ChannelFocus {
        get { eqConfiguration.channelFocus }
        set { eqConfiguration.channelFocus = newValue }
    }

    // MARK: - Components

    let deviceManager = DeviceManager()
    let volumeService: VolumeControlling
    let sampleRateService: SampleRateObserving
    let eqConfiguration: EQConfiguration
    let presetManager: PresetManager
    let meterStore: MeterStore
    let updateService = UpdateCheckService()

    // MARK: - Coordinators
    
    private(set) var deviceChangeCoordinator: DeviceChangeCoordinator
    private(set) var routingCoordinator: AudioRoutingCoordinator
    private(set) var correctionController: CorrectionController
    private(set) var channelController: ChannelController
    let exclusionStore = ExclusionStore()
    /// The real event journal (Settings › Driver › Activity).
    let activityJournal: ActivityJournal
    private(set) var callCliffController: CallCliffController
    private(set) var hearingController: HearingController
    private(set) var doseController: DoseController
    private(set) var autoPauseController: AutoPauseController
    private let systemDefaultObserver: SystemDefaultObserver
    nonisolated(unsafe) private var wakeObserver: NSObjectProtocol?
    private let compareModeTimer = CompareModeTimer()
    
    // MARK: - Private Properties
    
    let persistence: AppStatePersistence
    private let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "EqumaczerStore")
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Snapshot

    var currentSnapshot: AppStateSnapshot {
        AppStateSnapshot(
            globalBypass: eqConfiguration.globalBypass,
            inputGain: eqConfiguration.inputGain,
            outputGain: eqConfiguration.outputGain,
            autoPreampEnabled: eqConfiguration.autoPreampEnabled,
            loudnessEnabled: eqConfiguration.loudnessEnabled,
            loudnessStrength: eqConfiguration.loudnessStrength,
            loudnessMatchedBypassEnabled: eqConfiguration.loudnessMatchedBypassEnabled,
            spectrumEnabled: eqConfiguration.spectrumEnabled,
            channelEnabled: channelController.enabled,
            correctionEnabled: correctionController.enabled,
            channelMode: eqConfiguration.channelMode,
            channelFocus: eqConfiguration.channelFocus,
            leftState: eqConfiguration.leftState,
            rightState: eqConfiguration.rightState,
            inputDeviceID: manualModeEnabled ? routingCoordinator.selectedInputDeviceID : nil,
            outputDeviceID: routingCoordinator.selectedOutputDeviceID,
            bandwidthDisplayMode: bandwidthDisplayMode.rawValue,
            manualModeEnabled: manualModeEnabled,
            captureMode: routingCoordinator.captureMode.rawValue,
            automaticUpdateChecksEnabled: updateService.automaticChecksEnabled,
            lastUpdateCheckDate: updateService.lastCheckDate,
            recordingEnabled: recordingController.configuration.enabled,
            recordingIncludeMic: recordingController.configuration.includeMic,
            recordingMicrophoneUID: recordingController.configuration.microphoneUID,
            metersEnabled: meterStore.metersEnabled
        )
    }
    
    // MARK: - Initialization
    
    init(persistence: AppStatePersistence = AppStatePersistence(), channelStore: ChannelStore = ChannelStore(), activityJournal: ActivityJournal = ActivityJournal(), startAutomation: Bool = true, appVolumeStore: any AppVolumePersisting = AppVolumeStore()) {
        self.appVolumeStore = appVolumeStore
        self.persistence = persistence
        self.activityJournal = activityJournal
        
        // Load snapshot if exists
        let snapshot = persistence.load()
        
        // Initialize EQ configuration
        if let snapshot = snapshot {
            self.eqConfiguration = EQConfiguration(from: snapshot)
        } else {
            self.eqConfiguration = EQConfiguration()
        }
        
        // Initialize other components
        self.presetManager = PresetManager()
        self.meterStore = MeterStore(metersEnabled: snapshot?.metersEnabled ?? true)
        
        // Create services
        self.volumeService = DeviceVolumeService()
        self.sampleRateService = DeviceSampleRateService()
        
        // Create coordinators
        self.systemDefaultObserver = SystemDefaultObserver(deviceManager: deviceManager)
        self.deviceChangeCoordinator = DeviceChangeCoordinator(
            deviceEnumerator: deviceManager.enumerator
        )
        self.routingCoordinator = AudioRoutingCoordinator(
            deviceProvider: deviceManager,
            deviceChangeCoordinator: deviceChangeCoordinator,
            eqConfiguration: eqConfiguration,
            meterStore: meterStore,
            volumeService: volumeService,
            permissionService: AudioPermissionService(),
            systemDefaultObserver: systemDefaultObserver,
            sampleRateService: sampleRateService
        )
        self.correctionController = CorrectionController(
            eqConfiguration: eqConfiguration,
            routingCoordinator: routingCoordinator,
            volumeService: volumeService,
            deviceProvider: deviceManager
        )
        routingCoordinator.correctionController = correctionController
        self.channelController = ChannelController(
            eqConfiguration: eqConfiguration,
            routingCoordinator: routingCoordinator,
            store: channelStore
        )
        recordingController.onChange = { [weak routingCoordinator] configuration in
            routingCoordinator?.updateRecordingConfiguration(configuration)
        }
        routingCoordinator.pipelineManager.onRecordingMuteChanged = { [weak recordingController] muted in
            recordingController?.isMacMuted = muted
        }
        routingCoordinator.channelController = channelController

        self.callCliffController = CallCliffController(
            deviceManager: deviceManager,
            routingCoordinator: routingCoordinator,
            channelController: channelController
        )
        self.hearingController = HearingController(
            eqConfiguration: eqConfiguration,
            routingCoordinator: routingCoordinator
        )
        routingCoordinator.hearingController = hearingController
        self.doseController = DoseController()
        self.autoPauseController = AutoPauseController()
        autoPauseController.canDuckProvider = { [weak self] in self?.channelController.canDuck ?? false }
        autoPauseController.duckApplier = { [weak self] in self?.channelController.setDucked($0) }
        autoPauseController.modeProvider = { [weak self] in
            self?.channelController.state.duringCalls ?? .nothing
        }
        channelController.onActiveChannelChanged = { [weak self] channel in
            self?.activityJournal.record(.channel, "Channel switched to \(channel.displayName)")
        }
        DriverManager.shared.onEvent = { [weak self] text in
            self?.activityJournal.record(.driver, text)
        }
        observeRouteEvents()
        channelController.onCallStageChanged = { [weak autoPauseController] active in
            autoPauseController?.stageChanged(active)
        }
        correctionController.loudnessDeltaProvider = { [weak self] in
            self?.meterStore.loudnessMeter.bypassDeltaDB
        }
        // D2: the tap's exclusion provider — the listener's
        // never-process apps, resolved to live process objects
        // each time a tap is built.
        appVolumes = appVolumeStore.load()
        channelController.appVolumesProvider = { [weak self] in self?.appVolumes ?? [:] }
        channelController.excludedBundleIDsProvider = { [weak self] in Set(self?.exclusionStore.bundleIDs ?? []) }
        let exclusions = exclusionStore
        ProcessTapCapture.userExcludedProcessObjectIDsProvider = {
            ProcessObjectResolver.objectIDs(forBundleIDs: Set(exclusions.bundleIDs))
        }
        // D3: wake recovery — a pipeline live before sleep may
        // be dead on wake; rebuild it once devices settle.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        }
        doseController.levelProvider = { [weak self] in
            // PipelineManager holds a pipeline exactly while routing
            // runs (set on start, nilled on stop) — its presence is
            // the live signal.
            guard let self,
                  let pipeline = routingCoordinator.pipelineManager.renderPipeline
            else { return nil }
            let rmsDB = Double(pipeline.currentMeters().outputRmsDB.max() ?? -90)
            var volumeDB = 0.0
            if let uid = correctionController.currentDeviceUID,
               let device = deviceManager.device(forUID: uid),
               let scalar = volumeService.getDeviceVolumeScalar(deviceID: device.id),
               scalar > 0 {
                volumeDB = 20 * log10(Double(scalar))
            }
            return (rmsDB: rmsDB, volumeDB: volumeDB)
        }
        channelController.enabled = snapshot?.channelEnabled ?? true
        correctionController.enabled = snapshot?.correctionEnabled ?? true
        correctionController.start()
        channelController.start()
        callCliffController.start()
        hearingController.start()
        doseController.start()
        autoPauseController.start()
        
        // Log macOS system default output
        if let macDefault = systemDefaultObserver.getCurrentSystemDefaultOutputUID() {
            if let device = deviceManager.device(forUID: macDefault) {
                logger.info("EqumaczerStore.init: macOS default output: '\(device.name)' (uid=\(macDefault))")
            } else {
                logger.info("EqumaczerStore.init: macOS default output uid=\(macDefault) (device not in list)")
            }
        } else {
            logger.warning("EqumaczerStore.init: No macOS default output device found")
        }
        
        // Wire up callbacks
        compareModeTimer.onRevert = { [weak self] in
            self?.compareMode = .eq
        }
        
        persistence.setStore(self)
        
        // Restore app-level state
        if let snapshot = snapshot {
            logger.debug("Loading from snapshot: outputDeviceID=\(snapshot.outputDeviceID ?? "nil"), manualMode=\(snapshot.manualModeEnabled)")
            restoreAppPreferences(from: snapshot)
        } else {
            // First launch: automatic mode, use unified selection logic
            logger.info("First launch, no snapshot")
            routingCoordinator.manualModeEnabled = false
            restoreAutomaticOutputDevice(currentSelected: nil)
        }
        
        // Start observing system default changes
        systemDefaultObserver.startObserving()
        
        // Check if driver prompt should be shown (automatic mode without driver)
        // Defer to next run loop so onChange can observe the transition
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            // Forward driver prompt state from routing coordinator
            routingCoordinator.$showDriverPrompt
                .receive(on: DispatchQueue.main)
                .sink { [weak self] showPrompt in
                    guard let self else { return }
                    if showPrompt && !self.routingCoordinator.manualModeEnabled && !self.routingCoordinator.driverAccess.isReady {
                        self.logger.info("Automatic mode but driver not installed - showing prompt")
                    }
                }
                .store(in: &self.cancellables)
            
            if !routingCoordinator.manualModeEnabled && !routingCoordinator.driverAccess.isReady {
                self.logger.info("Automatic mode but driver not installed - showing prompt")
                self.routingCoordinator.showDriverPrompt = true
                self.routingCoordinator.routingStatus = .driverNotInstalled
            } else {
                // Driver visibility is now automatic
                if routingCoordinator.selectedOutputDeviceID != nil {
                    // Auto-start routing if devices are selected
                    self.routingCoordinator.reconfigureRouting()
                }
            }

        }
        
        // Wire up EQ configuration changes
        eqConfiguration.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        presetManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // Forward routing coordinator changes
        routingCoordinator.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Forward device manager changes (device list updates)
        deviceManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Forward update service changes
        updateService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Listen for app termination
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        
        // After all state is restored, check if settings differ from selected preset
        if presetManager.selectedPresetName != nil {
            let matches = presetManager.settingsMatchSelectedPreset(
                activeBandCount: eqConfiguration.activeBandCount,
                bands: eqConfiguration.bands,
                inputGain: eqConfiguration.inputGain,
                outputGain: eqConfiguration.outputGain
            )
            if !matches {
                presetManager.isModified = true
            }
        }
        updateService.onCheck = { [weak self] in
            guard let self else { return }
            self.persistence.save(self.currentSnapshot)
        }
        if startAutomation {
            sceneEngine.start(store: self)
            updateService.startAutomaticChecks()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    /// D3: after a wake, a still-present pipeline gets one
    /// rebuild once devices have had a moment to re-enumerate.
    /// The pipeline's presence is the guard both times — no
    /// routing, or routing stopped during the delay, means the
    /// wake is not ours to act on. Anything still missing after
    /// the rebuild belongs to the liveness watchdog, as before.
    private func handleWake() {
        guard routingCoordinator.pipelineManager.renderPipeline != nil else { return }
        routingCoordinator.handleWake()
    }
    
    // MARK: - App Lifecycle
    
    @objc private func handleAppWillTerminate() {
        logger.info("App terminating, stopping routing")
        routingCoordinator.stopRouting()
        // Driver visibility is now automatic
    }
    
    // MARK: - Routing Delegation
    
    func reconfigureRouting() {
        routingCoordinator.reconfigureRouting()
    }
    
    func stopRouting() {
        routingCoordinator.stopRouting()
    }
    
    func handleDriverInstalled() {
        routingCoordinator.handleDriverInstalled()
    }
    
    /// Switches to manual mode after requesting microphone permission.
    /// Manual mode uses HAL input capture, which requires microphone permission.
    /// - Returns: True if permission was granted and mode switched, false otherwise.
    @discardableResult
    @MainActor
    func switchToManualMode() async -> Bool {
        let switched = await routingCoordinator.requestMicPermissionAndSwitchToManualMode()
        if switched { activityJournal.record(.route, "Switched to manual routing") }
        return switched
    }
    
    /// Switches to manual mode synchronously (for compatibility).
    /// Note: This should only be used when permission is already known to be granted.
    func switchToManualMode() {
        routingCoordinator.switchToManualMode()
        activityJournal.record(.route, "Switched to manual routing")
    }
    
    /// Switches to automatic mode (uses shared memory capture by default).
    func switchToAutomaticMode() {
        routingCoordinator.switchToAutomaticMode()
        activityJournal.record(.route, "Switched to automatic routing")
    }
    
    // MARK: - EQ Control
    
    /// Updates the gain for a specific EQ band.
    func updateBandGain(index: Int, gain: Float) {
        eqConfiguration.updateBandGain(index: index, gain: gain)
        routingCoordinator.updateBandGain(index: index)
        presetManager.markAsModified()
    }
    
    /// Updates the Q factor for a specific EQ band.
    func updateBandQ(index: Int, q: Float) {
        eqConfiguration.updateBandQ(index: index, q: q)
        routingCoordinator.updateBandQ(index: index)
        presetManager.markAsModified()
    }
    
    /// Updates the frequency for a specific EQ band.
    func updateBandFrequency(index: Int, frequency: Float) {
        eqConfiguration.updateBandFrequency(index: index, frequency: frequency)
        routingCoordinator.updateBandFrequency(index: index)
        presetManager.markAsModified()
    }
    
    /// Updates the filter type for a specific EQ band.
    func updateBandFilterType(index: Int, filterType: FilterType) {
        eqConfiguration.updateBandFilterType(index: index, filterType: filterType)
        routingCoordinator.updateBandFilterType(index: index)
        presetManager.markAsModified()
    }
    
    /// Updates the bypass state for a specific EQ band.
    func updateBandBypass(index: Int, bypass: Bool) {
        eqConfiguration.updateBandBypass(index: index, bypass: bypass)
        routingCoordinator.updateBandBypass(index: index)
        presetManager.markAsModified()
    }
    
    /// Updates the band count and marks the preset as modified.
    func updateBandCount(_ count: Int) {
        let clamped = EQConfiguration.clampBandCount(count)
        bandCount = clamped
        presetManager.markAsModified()
    }
    
    /// Updates the input gain and marks the preset as modified.
    func updateInputGain(_ gain: Float) {
        inputGain = gain
        presetManager.markAsModified()
    }
    
    /// Updates the output gain and marks the preset as modified.
    func updateOutputGain(_ gain: Float) {
        outputGain = gain
        presetManager.markAsModified()
    }
    
    /// Sets the window reference for visibility checking.
    func setEqumaczerWindow(_ window: NSWindow?) {
        meterStore.setEqumaczerWindow(window)
    }
    
    // MARK: - Preset Management
    
    /// Saves the current EQ settings as a new preset.
    @discardableResult
    func saveCurrentAsPreset(named name: String) throws -> Preset {
        let preset = try presetManager.createPreset(
            named: name,
            from: eqConfiguration,
            inputGain: inputGain,
            outputGain: outputGain
        )
        presetManager.selectPreset(named: name)
        return preset
    }
    
    /// Updates the currently selected preset with current EQ settings.
    func updateCurrentPreset() throws {
        guard let currentName = presetManager.selectedPresetName else { return }
        try saveCurrentAsPreset(named: currentName)
    }
    
    /// Loads a preset and applies it to the EQ configuration.
    func loadPreset(_ preset: Preset) {
        let before = captureSoundState()
        // Apply settings to EQ configuration
        presetManager.applyPreset(preset, to: eqConfiguration)

        // Apply input/output gains
        inputGain = preset.settings.inputGain
        outputGain = preset.settings.outputGain

        // Reapply to audio engine if active
        routingCoordinator.reapplyConfiguration()

        // Mark as selected (not modified since we just loaded it)
        presetManager.selectPreset(named: preset.metadata.name)
        presetManager.recordUse(of: preset.metadata.name)
        isBypassed = preset.settings.globalBypass
        registerSoundUndo(label: "Load preset", state: before)
        activityJournal.record(.preset, "Loaded preset \(preset.metadata.name)")
    }

    private func deviceName(forUID uid: String) -> String {
        deviceManager.device(forUID: uid)?.name ?? uid
    }

    /// Routes the coordinator makes on its own (watchdog fallbacks)
    /// are recorded when they are announced, not guessed at.
    private func observeRouteEvents() {
        routingCoordinator.$captureFallbackNotice
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notice in
                self?.activityJournal.record(.route, notice)
            }
            .store(in: &cancellables)
    }
    
    /// Loads a preset by name.
    func loadPreset(named name: String) {
        guard let preset = presetManager.preset(named: name) else {
            logger.warning("Preset not found: \(name)")
            return
        }
        loadPreset(preset)
    }
    
    /// What the most recent Flatten erased, kept for one-click undo.
    struct FlattenSnapshot {
        let leftGains: [Float]
        let rightGains: [Float]
        let inputGain: Float
        let outputGain: Float
    }

    /// Band gains captured by the last Flatten; nil when there is
    /// nothing to undo.
    @Published private(set) var lastFlattenSnapshot: FlattenSnapshot?

    func clearFlattenReceipt() { lastFlattenSnapshot = nil }

    // MARK: - Never-process exclusions (D2)

    /// Excludes an app from processing and, when the Process
    /// Tap route is live, rebuilds the tap so the exclusion
    /// takes effect immediately. On the driver routes there is
    /// no tap to rebuild — the exclusion is recorded and applies
    /// whenever the tap runs (the pane says so).
    func excludeApp(bundleID: String, name: String) {
        exclusionStore.exclude(bundleID: bundleID, name: name)
        refreshTapExclusionsIfNeeded()
    }

    func includeApp(bundleID: String) {
        exclusionStore.include(bundleID: bundleID)
        refreshTapExclusionsIfNeeded()
    }

    private func refreshTapExclusionsIfNeeded() {
        channelController.refreshTapAssignments()
        // Only a live tap needs rebuilding — reconfigureRouting
        // would otherwise start routing that was never asked for.
        guard routingCoordinator.currentCaptureMode == .processTap,
              routingCoordinator.pipelineManager.renderPipeline != nil
        else { return }
        routingCoordinator.reconfigureRouting()
    }

    // MARK: - Undo stack (C4: undo-first over confirmation modals)

    private struct UndoEntry {
        let label: String
        let undo: () -> Bool
        let redo: (() -> Bool)?
    }
    private var undoStack: [UndoEntry] = []
    private var redoStack: [UndoEntry] = []
    @Published private(set) var undoLabel: String?
    @Published private(set) var redoLabel: String?

    func registerUndo(label: String, redo: (() -> Bool)? = nil, _ undo: @escaping () -> Bool) {
        undoStack.append(UndoEntry(label: label, undo: undo, redo: redo))
        if undoStack.count > 100 { undoStack.removeFirst(undoStack.count - 100) }
        undoLabel = label
        redoStack.removeAll()
        redoLabel = nil
    }

    func undoLastAction() {
        while let entry = undoStack.popLast() {
            if entry.undo() {
                if entry.redo != nil { redoStack.append(entry) }
                break
            }
        }
        undoLabel = undoStack.last?.label
        redoLabel = redoStack.last?.label
    }

    func redoLastAction() {
        guard let entry = redoStack.popLast() else { return }
        if entry.redo?() == true { undoStack.append(entry) }
        undoLabel = undoStack.last?.label
        redoLabel = redoStack.last?.label
    }

    /// Flattens all band gains to 0 dB while preserving current band configuration.
    func flattenBands() {
        let before = captureSoundState()
        lastFlattenSnapshot = FlattenSnapshot(
            leftGains: eqConfiguration.leftState.userEQ.bands.map(\.gain),
            rightGains: eqConfiguration.rightState.userEQ.bands.map(\.gain),
            inputGain: inputGain, outputGain: outputGain)
        for channel: EQChannelTarget in [.left, .right] {
            for i in 0..<EQConfiguration.maxBandCount {
                eqConfiguration.updateBandGain(index: i, gain: 0, channel: channel)
            }
        }
        inputGain = 0
        outputGain = 0
        isBypassed = false
        routingCoordinator.reapplyConfiguration()
        presetManager.markAsModified()
        registerSoundUndo(label: "Flatten", state: before)
    }

    /// Restores the band and input/output gains the last Flatten erased.
    func undoFlatten() {
        guard let snapshot = lastFlattenSnapshot else { return }
        for (index, gain) in snapshot.leftGains.enumerated() {
            eqConfiguration.updateBandGain(index: index, gain: gain, channel: .left)
        }
        for (index, gain) in snapshot.rightGains.enumerated() {
            eqConfiguration.updateBandGain(index: index, gain: gain, channel: .right)
        }
        inputGain = snapshot.inputGain
        outputGain = snapshot.outputGain
        lastFlattenSnapshot = nil

        routingCoordinator.reapplyConfiguration()
        presetManager.markAsModified()
    }

    /// Deletes the selected preset without a confirmation modal
    /// (C4): the preset is fetched first and the deletion
    /// registers its restore as an undo.
    func deleteSelectedPresetUndoable() {
        guard let name = presetManager.selectedPresetName else { return }
        deletePresetUndoable(named: name)
    }

    func deletePresetUndoable(named name: String) {
        guard let preset = presetManager.preset(named: name) else { return }
        let wasSelected = presetManager.selectedPresetName == name
        do { try presetManager.deletePreset(named: name) } catch { return }
        registerUndo(label: "Delete preset ‘\(name)’", redo: { [weak self] in
            guard let self else { return false }
            do { try self.presetManager.deletePreset(named: name); return true } catch { return false }
        }) { [weak self] in
            guard let self else { return false }
            try? self.presetManager.savePreset(preset)
            if wasSelected { self.presetManager.selectPreset(named: name) }
            return true
        }
    }

    /// Creates a new preset with 10 bands spread across the frequency spectrum.
    /// C4: the reset is destructive, so the current sound is
    /// captured first and the reset registers its undo — no
    /// confirmation, and no point of no return.
    func createNewPreset() {
        let before = captureSoundState()
        // Always reset to 10 bands with proper frequency spreading
        bandCount = 10
        _ = eqConfiguration.setActiveBandCount(10, preserveConfiguredBands: false)
        
        // Force frequency reset
        eqConfiguration.resetBandsWithFrequencySpread()
        
        // Reset gains
        inputGain = 0
        outputGain = 0
        isBypassed = false
        
        // Reapply to audio engine
        routingCoordinator.reapplyConfiguration()
        
        // Clear preset selection (this is a new unsaved preset)
        presetManager.selectPreset(named: nil)
        registerSoundUndo(label: "New preset (reset)", state: before)
    }
    
    // MARK: - Helpers

    /// Shared by startup, settings import and its Undo/Redo.
    func restoreAppPreferences(from snapshot: AppStateSnapshot) {
        updateService.automaticChecksEnabled = snapshot.automaticUpdateChecksEnabled
        updateService.lastCheckDate = snapshot.lastUpdateCheckDate
        recordingController.restore(snapshot)
        bandwidthDisplayMode = BandwidthDisplayMode(rawValue: snapshot.bandwidthDisplayMode) ?? .qFactor
        routingCoordinator.captureMode = CaptureMode.restored(from: snapshot.captureMode)
        routingCoordinator.manualModeEnabled = snapshot.manualModeEnabled
        if snapshot.manualModeEnabled {
            routingCoordinator.selectedInputDeviceID = snapshot.inputDeviceID
            routingCoordinator.selectedOutputDeviceID = snapshot.outputDeviceID
        } else {
            restoreAutomaticOutputDevice(currentSelected: snapshot.outputDeviceID)
        }
    }

    /// Determines the automatic-mode output device at startup using unified selection logic.
    /// Handles both snapshot restoration (currentSelected from saved state) and first launch (nil).
    private func restoreAutomaticOutputDevice(currentSelected: String?) {
        let macDefault = systemDefaultObserver.getCurrentSystemDefaultOutputUID()
        let selection = OutputDeviceSelection.determine(
            currentSelected: currentSelected,
            macDefault: macDefault,
            availableDevices: deviceManager.outputDevices
        )

        switch selection {
        case .preserveCurrent(let uid):
            routingCoordinator.selectedOutputDeviceID = uid
            logger.debug("Startup: preserving saved output device")

        case .useMacDefault(let uid):
            routingCoordinator.selectedOutputDeviceID = uid
            if let device = deviceManager.device(forUID: uid) {
                logger.debug("Startup: using macOS default '\(device.name)'")
            }

        case .useFallback:
            if let fallback = deviceManager.selectFallbackOutputDevice() {
                routingCoordinator.selectedOutputDeviceID = fallback.uid
                logger.info("Startup: using fallback output '\(fallback.name)'")
            } else {
                logger.error("Startup: no output device available")
            }
        }

        // Input is always driver in automatic mode
        routingCoordinator.selectedInputDeviceID = DRIVER_DEVICE_UID
    }

    static func clampGain(_ gain: Float) -> Float {
        AudioConstants.clampGain(gain)
    }
}
