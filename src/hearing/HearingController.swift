// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Combine
import Foundation
import os.log

/// Owns the hearing layer (layer 3): the listener's relative
/// per-ear Low/High shelves (A5), staged per channel — left shelves
/// to the left chain, right to the right. Its headroom is a
/// standalone preamp term from the hotter ear (see
/// `EQConfiguration.hearingPreampDB` for the terms).
@MainActor
final class HearingController: ObservableObject {
    @Published private(set) var state: HearingState

    private let eqConfiguration: EQConfiguration
    private let routingCoordinator: AudioRoutingCoordinator
    private let store: HearingStore
    private let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "HearingController")

    init(
        eqConfiguration: EQConfiguration,
        routingCoordinator: AudioRoutingCoordinator,
        store: HearingStore = HearingStore()
    ) {
        self.eqConfiguration = eqConfiguration
        self.routingCoordinator = routingCoordinator
        self.store = store
        self.state = store.load()
    }

    func start() {
        refresh()
    }

    // MARK: - User actions (the pane)

    func setEnabled(_ enabled: Bool) {
        state.enabled = enabled
        persistAndRefresh()
    }

    func setLeftLow(_ db: Float) { state.leftLowDB = Self.clamp(db); persistAndRefresh() }
    func setLeftHigh(_ db: Float) { state.leftHighDB = Self.clamp(db); persistAndRefresh() }
    func setRightLow(_ db: Float) { state.rightLowDB = Self.clamp(db); persistAndRefresh() }
    func setRightHigh(_ db: Float) { state.rightHighDB = Self.clamp(db); persistAndRefresh() }

    func setAudiogramThreshold(_ db: Float, ear: HearingEar, index: Int) {
        var audiogram = state.audiogram ?? Audiogram()
        audiogram.setThreshold(db, ear: ear, index: index)
        state.audiogram = audiogram
        persistAndRefresh()
    }

    func setAudiogramInUse(_ inUse: Bool) {
        guard var audiogram = state.audiogram else { return }
        audiogram.inUse = inUse
        state.audiogram = audiogram
        persistAndRefresh()
    }

    func clearAudiogram() {
        state.audiogram = nil
        persistAndRefresh()
    }

    func reset() {
        state.reset()
        persistAndRefresh()
    }

    private static func clamp(_ db: Float) -> Float {
        min(max(db, HearingState.rangeDB.lowerBound), HearingState.rangeDB.upperBound)
    }

    private func persistAndRefresh() {
        store.save(state)
        refresh()
    }

    // MARK: - Staging

    /// Restages the hearing layer per channel. Called on any state
    /// edit and on pipeline reapply (via the routing coordinator,
    /// like the other owned layers).
    func refresh() {
        let stager = routingCoordinator.eqStager
        let leftBands = HearingComposition.leftBands(for: state)
        let rightBands = HearingComposition.rightBands(for: state)

        let leftCoefficients = stager.designedCoefficients(for: leftBands, count: leftBands.count)
        let rightCoefficients = stager.designedCoefficients(for: rightBands, count: rightBands.count)

        // One input gain serves both ears: the hotter ear's need.
        let leftPreamp = HeadroomAnalyzer.recommendedAutoPreampDB(
            svfCoefficients: leftCoefficients,
            bypassFlags: leftBands.map { $0.bypass },
            activeBandCount: leftBands.count,
            sampleRate: stager.sampleRate
        )
        let rightPreamp = HeadroomAnalyzer.recommendedAutoPreampDB(
            svfCoefficients: rightCoefficients,
            bypassFlags: rightBands.map { $0.bypass },
            activeBandCount: rightBands.count,
            sampleRate: stager.sampleRate
        )

        let previousEffective = eqConfiguration.effectiveInputGainDB
        eqConfiguration.setHearingPreampDB(min(Float(leftPreamp), Float(rightPreamp), 0))
        if eqConfiguration.effectiveInputGainDB != previousEffective {
            routingCoordinator.updateInputGain(
                linear: AudioMath.dbToLinear(eqConfiguration.effectiveInputGainDB)
            )
        }

        let pipeline = routingCoordinator.pipelineManager.renderPipeline
        pipeline?.stageFullEQUpdate(
            channel: .left,
            layerIndex: EQLayerConstants.hearingLayerIndex,
            coefficients: leftCoefficients,
            bypassFlags: leftBands.map { $0.bypass },
            activeBandCount: leftBands.count,
            layerBypass: eqConfiguration.globalBypass
        )
        pipeline?.stageFullEQUpdate(
            channel: .right,
            layerIndex: EQLayerConstants.hearingLayerIndex,
            coefficients: rightCoefficients,
            bypassFlags: rightBands.map { $0.bypass },
            activeBandCount: rightBands.count,
            layerBypass: eqConfiguration.globalBypass
        )
    }
}
