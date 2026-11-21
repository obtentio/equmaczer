// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
// EQCoefficientStager.swift
// Stages EQ coefficient updates from configuration to render pipeline

import OSLog

/// Stages EQ coefficient updates from `EQConfiguration` to `RenderPipeline`.
/// Separates the DSP concern of coefficient calculation from routing orchestration.
@MainActor
final class EQCoefficientStager {

    // MARK: - Dependencies

    private let eqConfiguration: EQConfiguration
    private weak var renderPipeline: RenderPipeline?

    // MARK: - State

    /// Current sample rate for coefficient calculations.
    /// Updated when pipeline starts or sample rate changes.
    private var currentSampleRate: Double = 48000.0

    /// The sample rate designs are currently made at.
    var sampleRate: Double { currentSampleRate }

    private let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "EQCoefficientStager")

    // MARK: - Initialization

    init(eqConfiguration: EQConfiguration) {
        self.eqConfiguration = eqConfiguration
    }

    // MARK: - Pipeline Lifecycle

    func setRenderPipeline(_ pipeline: RenderPipeline?) {
        renderPipeline = pipeline
    }

    func setCurrentSampleRate(_ rate: Double) {
        currentSampleRate = rate
    }

    // MARK: - Single Band Updates

    /// Updates a band's gain by recalculating and staging coefficients.
    func updateBandGain(index: Int) {
        guard index >= 0 && index < eqConfiguration.bands.count else { return }
        let config = eqConfiguration.bands[index]
        stageBandCoefficients(index: index, config: config)
    }

    /// Updates a band's Q factor by recalculating and staging coefficients.
    func updateBandQ(index: Int) {
        guard index >= 0 && index < eqConfiguration.bands.count else { return }
        let config = eqConfiguration.bands[index]
        stageBandCoefficients(index: index, config: config)
    }

    /// Updates a band's frequency by recalculating and staging coefficients.
    func updateBandFrequency(index: Int) {
        guard index >= 0 && index < eqConfiguration.bands.count else { return }
        let config = eqConfiguration.bands[index]
        stageBandCoefficients(index: index, config: config)
    }

    /// Updates a band's filter type by recalculating and staging coefficients.
    func updateBandFilterType(index: Int) {
        guard index >= 0 && index < eqConfiguration.bands.count else { return }
        let config = eqConfiguration.bands[index]
        stageBandCoefficients(index: index, config: config)
    }

    /// Updates a band's bypass state.
    func updateBandBypass(index: Int) {
        guard index >= 0 && index < eqConfiguration.bands.count else { return }
        let config = eqConfiguration.bands[index]
        stageBandCoefficients(index: index, config: config)
    }

    /// Returns the current band capacity from EQConfiguration.
    func currentBandCapacity() -> Int {
        eqConfiguration.activeBandCount
    }

    /// Reapplies all coefficients from the current configuration.
    func reapplyConfiguration() {
        reapplyAllCoefficients()
    }

    // MARK: - Private Coefficient Helpers

    /// Stages coefficients for a single band.
    private func stageBandCoefficients(index: Int, config: EQBandConfiguration) {
        let coefficients = designCoefficient(for: config, index: index)

        // Use channel mode and editing channel from configuration
        let target: EQChannelTarget = eqConfiguration.channelMode == .linked ? .both :
            (eqConfiguration.channelFocus == .left ? .left : .right)

        renderPipeline?.updateBandCoefficients(
            channel: target,
            layerIndex: EQLayerConstants.userEQLayerIndex,
            bandIndex: index,
            coefficients: coefficients,
            bypass: config.bypass
        )

        renderPipeline?.setLimiterLinked(eqConfiguration.channelMode == .linked)

        refreshAutoPreamp()
    }

    /// Designs one band's coefficients with the Nyquist-decramped TPT SVF
    /// designer — the single designer used for every channel and every
    /// update path. Invalid parameters or unstable results stage as
    /// passthrough, exactly as before.
    private func designCoefficient(for config: EQBandConfiguration, index: Int) -> SVFCoefficients {
        let frequency = Double(config.frequency)
        let q = Double(config.q)
        let gain = Double(config.gain)

        // Validate parameters before calculation
        let paramResult = BiquadValidator.validate(
            type: config.filterType,
            sampleRate: currentSampleRate,
            frequency: frequency,
            q: q,
            gain: gain
        )
        if case .invalid(let message) = paramResult {
            logger.warning("Band \(index) invalid parameters: \(message) — using passthrough")
            return .identity
        }
        if case .warning(let message) = paramResult {
            logger.debug("Band \(index) parameter warning: \(message)")
        }

        let coefficients = SVFMath.calculateDecrampedSVF(
            type: config.filterType,
            sampleRate: currentSampleRate,
            frequency: frequency,
            q: q,
            gain: gain
        )

        // Validate coefficient stability — unstable filters can damage speakers.
        // Stability is a property of the section's poles, checked here on the
        // equivalent biquad form (analysis only; the staged value stays SVF).
        let biquadForm = coefficients.toBiquadCoefficients()
        if !BiquadValidator.isFinite(biquadForm) {
            logger.warning("Band \(index) coefficients are non-finite — using passthrough")
            return .identity
        }
        if !BiquadValidator.isStable(biquadForm) {
            logger.warning("Band \(index) coefficients are unstable — using passthrough")
            return .identity
        }

        return coefficients
    }

    /// Designs coefficients for the first `count` bands of one channel.
    /// Both channels go through this one path, so left and right can never
    /// be designed by different code again.
    func designedCoefficients(for bands: [EQBandConfiguration], count: Int) -> [SVFCoefficients] {
        let limit = min(count, bands.count)
        var result: [SVFCoefficients] = []
        result.reserveCapacity(limit)
        for index in 0..<limit {
            result.append(designCoefficient(for: bands[index], index: index))
        }
        return result
    }

    /// Recalculates and stages all coefficients for all active bands.
    private func reapplyAllCoefficients() {
        let activeCount = eqConfiguration.activeBandCount

        // Get the appropriate bands based on channel mode
        let leftBands = eqConfiguration.leftState.userEQ.bands
        let rightBands = eqConfiguration.rightState.userEQ.bands

        // One designer for both channels. (Previously the right channel was
        // designed with the legacy RBJ biquad designer on this path, so a
        // preset load produced a different treble curve in each ear.)
        let leftCoefficients = designedCoefficients(for: leftBands, count: activeCount)
        let leftBypassFlags = leftBands.prefix(leftCoefficients.count).map(\.bypass)

        // Determine channel target based on mode
        let leftTarget: EQChannelTarget = eqConfiguration.channelMode == .linked ? .both : .left

        renderPipeline?.stageFullEQUpdate(
            channel: leftTarget,
            layerIndex: EQLayerConstants.userEQLayerIndex,
            coefficients: leftCoefficients,
            bypassFlags: leftBypassFlags,
            activeBandCount: activeCount,
            layerBypass: eqConfiguration.globalBypass || !eqConfiguration.userEQEnabled
        )

        // In stereo mode, also stage right channel coefficients
        if eqConfiguration.channelMode == .stereo {
            let rightCoefficients = designedCoefficients(for: rightBands, count: activeCount)
            let rightBypassFlags = rightBands.prefix(rightCoefficients.count).map(\.bypass)

            renderPipeline?.stageFullEQUpdate(
                channel: .right,
                layerIndex: EQLayerConstants.userEQLayerIndex,
                coefficients: rightCoefficients,
                bypassFlags: rightBypassFlags,
                activeBandCount: activeCount,
                layerBypass: eqConfiguration.globalBypass || !eqConfiguration.userEQEnabled
            )
        }

        renderPipeline?.setLimiterLinked(eqConfiguration.channelMode == .linked)

        refreshAutoPreamp()
    }

    // MARK: - Auto-Preamp

    /// Recomputes the auto-preamp from the exact composite transfer function
    /// of the currently configured bands and, when the effective input gain
    /// changes, pushes it to the render pipeline.
    ///
    /// The preamp is a single input-stage gain, so in stereo mode it must
    /// cover the hotter of the two channels.
    private func refreshAutoPreamp() {
        let activeCount = eqConfiguration.activeBandCount
        let bypassed = eqConfiguration.globalBypass || !eqConfiguration.userEQEnabled || activeCount == 0

        var channels: [EQConfiguration.CascadeLayerData.ChannelData] = []
        var recommended = 0.0
        if activeCount > 0 {
            let left = cascadeChannel(
                for: eqConfiguration.leftState.userEQ.bands,
                activeCount: activeCount
            )
            channels.append(left.data)
            recommended = left.recommended

            if eqConfiguration.channelMode == .stereo {
                let right = cascadeChannel(
                    for: eqConfiguration.rightState.userEQ.bands,
                    activeCount: activeCount
                )
                channels.append(right.data)
                recommended = min(recommended, right.recommended)
            }
        }

        let previousEffective = eqConfiguration.effectiveInputGainDB
        eqConfiguration.updateManualCascade(EQConfiguration.CascadeLayerData(
            channels: channels,
            recommendedPreampDB: recommended,
            sampleRate: currentSampleRate,
            isBypassed: bypassed
        ))
        let newEffective = eqConfiguration.effectiveInputGainDB
        if newEffective != previousEffective {
            renderPipeline?.updateInputGain(linear: AudioMath.dbToLinear(newEffective))
        }
    }

    /// One channel's cascade data: designed coefficients, the
    /// analyser's grid magnitude vector, and the recommended
    /// auto-preamp for the channel on its own.
    private func cascadeChannel(
        for bands: [EQBandConfiguration],
        activeCount: Int
    ) -> (data: EQConfiguration.CascadeLayerData.ChannelData, recommended: Double) {
        let coefficients = designedCoefficients(for: bands, count: activeCount)
        let bypassFlags = bands.prefix(coefficients.count).map(\.bypass)
        let candidateFrequencies = bands.prefix(coefficients.count).map { Double($0.frequency) }
        let recommended = HeadroomAnalyzer.recommendedAutoPreampDB(
            svfCoefficients: coefficients,
            bypassFlags: bypassFlags,
            activeBandCount: activeCount,
            sampleRate: currentSampleRate,
            candidateFrequencies: candidateFrequencies
        )
        let vector = HeadroomAnalyzer.compositeMagnitudeDBVector(
            svfCoefficients: coefficients,
            bypassFlags: bypassFlags,
            activeBandCount: activeCount,
            sampleRate: currentSampleRate
        )
        let data = EQConfiguration.CascadeLayerData.ChannelData(
            coefficients: coefficients,
            bypassFlags: bypassFlags,
            activeBandCount: activeCount,
            candidateFrequencies: candidateFrequencies,
            magnitudeDB: vector
        )
        return (data, recommended)
    }
}
