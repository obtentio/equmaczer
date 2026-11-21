// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation
import os.log

// MARK: - Channel Editing Target

/// Which channel to edit in stereo mode.
/// In linked mode, this is ignored (both channels edited together).
enum ChannelFocus: String, Codable, Sendable {
    case left
    case right
}

/// Configuration for a single EQ band.
///
/// Q (quality factor) is stored natively. Bandwidth in octaves is a display preference
/// that can be converted to/from Q using `BandwidthConverter`. Q is the value used
/// directly by the biquad coefficient calculations.
struct EQBandConfiguration: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case frequency
        case q
        case bandwidth  // Legacy: for backward compatibility with old presets
        case gain
        case filterType
        case bypass
    }

    init(frequency: Float, q: Float, gain: Float, filterType: FilterType, bypass: Bool) {
        self.frequency = frequency
        self.q = q
        self.gain = gain
        self.filterType = filterType
        self.bypass = bypass
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try container.decode(Float.self, forKey: .frequency)
        gain = try container.decode(Float.self, forKey: .gain)
        let filterTypeRaw = try container.decode(Int.self, forKey: .filterType)
        filterType = FilterType(validatedRawValue: filterTypeRaw) ?? .parametric
        bypass = try container.decode(Bool.self, forKey: .bypass)

        // New format: q field (preferred)
        // Legacy format: bandwidth field (convert to Q)
        if let q = try container.decodeIfPresent(Float.self, forKey: .q) {
            self.q = q
        } else if let bandwidth = try container.decodeIfPresent(Float.self, forKey: .bandwidth) {
            // Legacy: convert bandwidth (octaves) to Q
            self.q = BandwidthConverter.bandwidthToQ(bandwidth)
        } else {
            self.q = EQConfiguration.defaultQ
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(q, forKey: .q)
        try container.encode(gain, forKey: .gain)
        try container.encode(filterType.rawValue, forKey: .filterType)
        try container.encode(bypass, forKey: .bypass)
    }

    var frequency: Float
    var q: Float
    var gain: Float
    var filterType: FilterType
    var bypass: Bool

    /// Default parametric band configuration.
    static func parametric(frequency: Float, q: Float = EQConfiguration.defaultQ) -> EQBandConfiguration {
        EQBandConfiguration(
            frequency: frequency,
            q: q,
            gain: 0,
            filterType: .parametric,
            bypass: false
        )
    }
}

/// Stores EQ configuration independently of any AVAudioEngine instance.
/// This allows settings to be stored and modified without triggering
/// audio hardware initialization.
@MainActor
final class EQConfiguration: ObservableObject {
    // MARK: - Constants

    nonisolated static let maxBandCount: Int = 64
    nonisolated static let defaultBandCount: Int = 10
    /// Default Q factor for EQ bands (~1 octave bandwidth, industry standard).
    nonisolated static let defaultQ: Float = 1.41

    // MARK: - Published Properties

    /// Independent manual layer switch; System EQ still bypasses the whole cascade.
    var userEQEnabled: Bool {
        get { !leftState.userEQ.bypass }
        set {
            leftState.userEQ.bypass = !newValue
            rightState.userEQ.bypass = !newValue
        }
    }

    /// Global bypass for all EQ bands.
    @Published var globalBypass: Bool = false

    /// Input gain applied before EQ processing (in dB).
    @Published var inputGain: Float = 0

    /// Output gain applied after EQ processing (in dB).
    @Published var outputGain: Float = 0

    /// Whether automatic preamp headroom compensation is applied.
    /// When enabled, `autoPreampDB` is added to `inputGain` so the composite
    /// EQ boost can never clip the input stage.
    @Published var autoPreampEnabled: Bool = true {
        didSet { recomputeCascadePreamp() }
    }

    /// Auto-preamp attenuation in dB (always <= 0), computed by
    /// `EQCoefficientStager` from the exact composite transfer function
    /// (`HeadroomAnalyzer`). Zero when no active band boosts the composite
    /// response above unity.
    @Published private(set) var autoPreampDB: Float = 0

    /// Correction-layer preamp in dB (always <= 0), owned by
    /// `CorrectionController`: the active device profile's preamp, with
    /// extra attenuation whenever the composed correction layer (profile
    /// bands, preference trims, loudness shelves) would otherwise boost
    /// the composite response above unity — whichever is more protective.
    @Published private(set) var correctionPreampDB: Float = 0

    /// Channel-layer preamp in dB (always <= 0), owned by
    /// `ChannelController` (A3): the active channel treatment's own
    /// preamp need, computed standalone from that layer alone. This
    /// is deliberately NOT folded into the two-layer marginal math
    /// in `recomputeCascadePreamp()`: standalone over-cuts when the
    /// layers peak at different frequencies, which is the safe
    /// direction, and the correction layer's refinement was earned
    /// by being always-on — the channel layer is usually Flat.
    @Published private(set) var channelPreampDB: Float = 0

    /// Hearing-layer preamp in dB (always <= 0), owned by
    /// `HearingController` (A5): the hotter ear's standalone preamp
    /// need, on the same deliberate terms as `channelPreampDB`.
    @Published private(set) var hearingPreampDB: Float = 0

    /// Input gain actually applied before EQ processing (in dB): the user's
    /// input gain plus auto-preamp attenuation when enabled, plus the
    /// correction layer's preamp, plus the channel and hearing layers',
    /// plus the blind A/B test's level-match trim (C2 — zero outside a
    /// test, clamped to ±6 dB: matching is for judging, not a gain stage).
    var effectiveInputGainDB: Float {
        inputGain + (autoPreampEnabled ? autoPreampDB : 0) + correctionPreampDB + channelPreampDB + hearingPreampDB + blindTrimDB
    }

    /// Records a newly computed auto-preamp value. Called by the stager
    /// whenever coefficients are restaged.
    func setAutoPreampDB(_ db: Float) {
        let clamped = min(0, db)
        guard abs(clamped - autoPreampDB) > 0.001 else { return }
        autoPreampDB = clamped
    }

    /// Records a newly computed correction preamp. Called by
    /// `CorrectionController` whenever the correction layer is recomposed.
    func setCorrectionPreampDB(_ db: Float) {
        let clamped = min(0, db)
        guard abs(clamped - correctionPreampDB) > 0.001 else { return }
        correctionPreampDB = clamped
    }

    /// Records a newly computed channel preamp. Called by
    /// `ChannelController` whenever the channel layer is restaged.
    func setChannelPreampDB(_ db: Float) {
        let clamped = min(0, db)
        guard abs(clamped - channelPreampDB) > 0.001 else { return }
        channelPreampDB = clamped
    }

    /// Records a newly computed hearing preamp. Called by
    /// `HearingController` whenever the hearing layer is restaged.
    func setHearingPreampDB(_ db: Float) {
        let clamped = min(0, db)
        guard abs(clamped - hearingPreampDB) > 0.001 else { return }
        hearingPreampDB = clamped
    }

    /// The blind A/B test's level-match trim (C2). Unlike the
    /// layer preamps this one may boost — it exists only while a
    /// test runs and returns to zero when the test ends.
    @Published private(set) var blindTrimDB: Float = 0

    /// Records the blind test's trim. Called by
    /// `BlindABController` as each side's loudness is measured.
    func setBlindTrimDB(_ db: Float) {
        let clamped = max(-6, min(6, db))
        guard abs(clamped - blindTrimDB) > 0.001 else { return }
        blindTrimDB = clamped
    }

    // MARK: - Unified cascade preamp

    /// One layer's contribution to the unified cascade preamp: its
    /// grid magnitude vector(s), its own recommended preamp, and the
    /// exact-evaluation inputs needed to refine the cascade peak at
    /// the layers' candidate frequencies.
    struct CascadeLayerData {
        struct ChannelData {
            var coefficients: [SVFCoefficients]
            var bypassFlags: [Bool]
            var activeBandCount: Int
            var candidateFrequencies: [Double]
            var magnitudeDB: [Float]
        }
        /// One entry in linked/mono operation, two in stereo (manual
        /// layer only; the correction layer always has one).
        var channels: [ChannelData]
        /// The layer's own recommended preamp (dB, <= 0), including
        /// the inter-sample-peak safety margin.
        var recommendedPreampDB: Double
        var sampleRate: Double
        /// True when the layer is not processing (global bypass):
        /// its preamp is forced to zero and unification is skipped.
        var isBypassed: Bool = false
    }

    private(set) var manualCascade: CascadeLayerData?
    private(set) var correctionCascade: CascadeLayerData?
    private(set) var correctionProfilePreampDB: Float = 0

    /// Called by the stager whenever the manual layer restages.
    func updateManualCascade(_ data: CascadeLayerData) {
        manualCascade = data
        recomputeCascadePreamp()
    }

    /// Called by `CorrectionController` whenever the correction
    /// layer is recomposed.
    func updateCorrectionCascade(_ data: CascadeLayerData, profilePreampDB: Float) {
        correctionCascade = data
        correctionProfilePreampDB = profilePreampDB
        recomputeCascadePreamp()
    }

    /// Derives both preamps from the two layers' cascade data.
    ///
    /// The manual preamp keeps its own layer's basis (it is what
    /// Zone D's ceiling band displays). When auto-preamp is on and
    /// both layers are live at the same sample rate, the correction
    /// preamp becomes only the *marginal* headroom the true cascade
    /// peak needs above the manual preamp — summing the two layers'
    /// separate peaks over-cuts whenever they peak at different
    /// frequencies (or one cuts where the other boosts). When the
    /// correction layer cuts where the manual layer boosts, the
    /// total stays at the manual preamp by design: the displayed
    /// value is never undercut. The profile's declared preamp
    /// remains a floor in every mode.
    private func recomputeCascadePreamp() {
        guard manualCascade != nil || correctionCascade != nil else { return }

        if let manual = manualCascade {
            setAutoPreampDB(manual.isBypassed ? 0 : Float(manual.recommendedPreampDB))
        }

        let standalone = min(
            correctionProfilePreampDB,
            Float(correctionCascade?.recommendedPreampDB ?? 0),
            0
        )

        guard autoPreampEnabled,
              let manual = manualCascade, !manual.isBypassed,
              let correction = correctionCascade,
              manual.sampleRate == correction.sampleRate,
              let manualChannel = manual.channels.first,
              let corrChannel = correction.channels.first,
              manualChannel.magnitudeDB.count == corrChannel.magnitudeDB.count,
              !manualChannel.magnitudeDB.isEmpty
        else {
            setCorrectionPreampDB(standalone)
            return
        }

        var peak = -Double.greatestFiniteMagnitude
        for channel in manual.channels where channel.magnitudeDB.count == corrChannel.magnitudeDB.count {
            for index in channel.magnitudeDB.indices {
                let sum = Double(channel.magnitudeDB[index]) + Double(corrChannel.magnitudeDB[index])
                if sum > peak { peak = sum }
            }
            for frequency in channel.candidateFrequencies + corrChannel.candidateFrequencies {
                let manualGain = HeadroomAnalyzer.compositeGainDB(
                    svfCoefficients: channel.coefficients,
                    bypassFlags: channel.bypassFlags,
                    activeBandCount: channel.activeBandCount,
                    sampleRate: manual.sampleRate,
                    at: frequency
                )
                let correctionGain = HeadroomAnalyzer.compositeGainDB(
                    svfCoefficients: corrChannel.coefficients,
                    bypassFlags: corrChannel.bypassFlags,
                    activeBandCount: corrChannel.activeBandCount,
                    sampleRate: manual.sampleRate,
                    at: frequency
                )
                if manualGain + correctionGain > peak { peak = manualGain + correctionGain }
            }
        }
        guard peak > -1e20 else {
            setCorrectionPreampDB(standalone)
            return
        }

        let cascadePeak = peak > 0 ? peak + 0.2 : peak
        let marginal = -cascadePeak - Double(autoPreampDB)
        setCorrectionPreampDB(min(correctionProfilePreampDB, Float(marginal), 0))
    }

    /// Whether ISO 226 loudness compensation is active. Off by default:
    /// unlike auto-preamp (invisible headroom safety), loudness
    /// compensation changes tonal character, so it is opt-in.
    @Published var loudnessEnabled: Bool = false

    /// Loudness compensation strength, 0...1. Doubles as the calibration
    /// for the volume-to-phon estimate, which varies per system.
    @Published var loudnessStrength: Float = 0.5

    /// Whether the flat-compare path is gain-matched to the EQ path's
    /// measured loudness (BS.1770 delta), so A/B comparisons are not
    /// biased by the EQ's own loudness change. Always enabled.
    let loudnessMatchedBypassEnabled = true

    /// Whether the live output spectrum shows behind the band stage.
    @Published var spectrumEnabled: Bool = true

    /// Channel processing mode.
    /// - linked: Same EQ applied to both L and R (default)
    /// - stereo: Independent L and R EQ settings
    @Published var channelMode: ChannelMode = .linked

    /// Which channel is currently being edited in stereo mode.
    /// In linked mode, this is ignored.
    @Published var channelFocus: ChannelFocus = .left

    /// Current number of active bands exposed to the UI and audio engine.
    /// In linked mode, this is the band count for both channels.
    /// In stereo mode, this is the max of left and right band counts.
    @Published private(set) var activeBandCount: Int

    /// Band count for the currently focused channel.
    /// In linked mode, returns activeBandCount.
    /// In stereo mode, returns the band count of the focused channel.
    var focusedChannelBandCount: Int {
        switch channelMode {
        case .linked:
            return activeBandCount
        case .stereo:
            return channelFocus == .left
                ? leftState.userEQ.activeBandCount
                : rightState.userEQ.activeBandCount
        }
    }

    /// Per-channel EQ state.
    /// Left channel state is used for linked mode.
    @Published private(set) var leftState: ChannelEQState
    @Published private(set) var rightState: ChannelEQState

    /// Configuration for all bands (always sized to `maxBandCount`).
    /// Returns bands for the currently edited channel:
    /// - In linked mode: left channel bands (both channels have same settings)
    /// - In stereo mode: bands for the channel being edited
    var bands: [EQBandConfiguration] {
        switch channelMode {
        case .linked:
            return leftState.userEQ.bands
        case .stereo:
            return channelFocus == .left
                ? leftState.userEQ.bands
                : rightState.userEQ.bands
        }
    }

    // MARK: - Initialization

    init(initialBandCount: Int = EQConfiguration.defaultBandCount) {
        leftState = ChannelEQState(layers: [.userEQ(bandCount: initialBandCount)])
        rightState = ChannelEQState(layers: [.userEQ(bandCount: initialBandCount)])
        activeBandCount = EQConfiguration.clampBandCount(initialBandCount)
    }

    convenience init(from snapshot: AppStateSnapshot) {
        // Snapshot decoding handles legacy migration, so we can use states directly
        let bandCount = snapshot.leftState.userEQ.activeBandCount

        self.init(initialBandCount: bandCount)
        restore(from: snapshot)
    }

    /// Shared by launch restoration and live settings import.
    func restore(from snapshot: AppStateSnapshot) {
        globalBypass = snapshot.globalBypass
        inputGain = snapshot.inputGain
        outputGain = snapshot.outputGain
        autoPreampEnabled = snapshot.autoPreampEnabled
        loudnessEnabled = snapshot.loudnessEnabled
        loudnessStrength = snapshot.loudnessStrength
        spectrumEnabled = snapshot.spectrumEnabled
        channelMode = snapshot.channelMode
        channelFocus = snapshot.channelFocus

        // Restore channel states directly (migration handled in AppStateSnapshot.decode)
        leftState = snapshot.leftState
        rightState = snapshot.rightState

        // Cover both channels when restoring independent band counts
        activeBandCount = snapshot.channelMode == .linked
            ? snapshot.leftState.userEQ.activeBandCount
            : max(snapshot.leftState.userEQ.activeBandCount, snapshot.rightState.userEQ.activeBandCount)
    }

    // MARK: - Band Count Management

    /// Sets the number of active bands, clamping to the supported range.
    /// In linked mode, sets both channels. In stereo mode, sets only the channel being edited.
    /// - Parameters:
    ///   - newValue: The desired number of bands.
    ///   - preserveConfiguredBands: If true and bands have been modified (non-zero gains),
    ///     only add/remove bands from the right side. If false, respread all bands across the spectrum.
    /// - Returns: The clamped value actually set.
    @discardableResult
    func setActiveBandCount(_ newValue: Int, preserveConfiguredBands: Bool = true) -> Int {
        let clamped = EQConfiguration.clampBandCount(newValue)

        switch channelMode {
        case .linked:
            // Linked mode: set both channels
            let oldCount = activeBandCount
            guard clamped != oldCount else { return clamped }

            if preserveConfiguredBands && hasModifiedBands(upTo: min(oldCount, clamped)) {
                // Bands have been configured - add/remove from right only
                if clamped > oldCount {
                    // Adding bands: extend frequencies to the right
                    let lastFreq = bands[oldCount - 1].frequency
                    let maxFreq: Float = 26000
                    let newBandCount = clamped - oldCount
                    let ratio = pow(maxFreq / lastFreq, 1 / Float(newBandCount + 1))

                    // Update both channels
                    for i in oldCount..<clamped {
                        let freq = lastFreq * pow(ratio, Float(i - oldCount + 1))
                        leftState.userEQ.bands[i] = EQBandConfiguration.parametric(
                            frequency: freq,
                            q: EQConfiguration.defaultQ
                        )
                        rightState.userEQ.bands[i] = EQBandConfiguration.parametric(
                            frequency: freq,
                            q: EQConfiguration.defaultQ
                        )
                    }
                }
                // Removing bands: just decrease count, existing bands preserved
            } else {
                // No modifications - respread all bands across full spectrum
                let frequencies = EQConfiguration.frequenciesForBandCount(clamped)
                for (index, frequency) in frequencies.enumerated() {
                    let band = EQBandConfiguration.parametric(
                        frequency: frequency,
                        q: EQConfiguration.defaultQ
                    )
                    leftState.userEQ.bands[index] = band
                    rightState.userEQ.bands[index] = band
                }
            }

            // Update active band count in both channels
            leftState.userEQ.activeBandCount = clamped
            rightState.userEQ.activeBandCount = clamped
            activeBandCount = clamped

        case .stereo:
            // Stereo mode: set only the channel being edited
            if channelFocus == .left {
                let oldCount = leftState.userEQ.activeBandCount
                guard clamped != oldCount else { return clamped }

                if preserveConfiguredBands && hasModifiedBands(upTo: min(oldCount, clamped), channel: .left) {
                    if clamped > oldCount {
                        let lastFreq = leftState.userEQ.bands[oldCount - 1].frequency
                        let maxFreq: Float = 26000
                        let newBandCount = clamped - oldCount
                        let ratio = pow(maxFreq / lastFreq, 1 / Float(newBandCount + 1))

                        for i in oldCount..<clamped {
                            let freq = lastFreq * pow(ratio, Float(i - oldCount + 1))
                            leftState.userEQ.bands[i] = EQBandConfiguration.parametric(
                                frequency: freq,
                                q: EQConfiguration.defaultQ
                            )
                        }
                    }
                } else {
                    let frequencies = EQConfiguration.frequenciesForBandCount(clamped)
                    for (index, frequency) in frequencies.enumerated() {
                        leftState.userEQ.bands[index] = EQBandConfiguration.parametric(
                            frequency: frequency,
                            q: EQConfiguration.defaultQ
                        )
                    }
                }
                leftState.userEQ.activeBandCount = clamped
            } else {
                let oldCount = rightState.userEQ.activeBandCount
                guard clamped != oldCount else { return clamped }

                if preserveConfiguredBands && hasModifiedBands(upTo: min(oldCount, clamped), channel: .right) {
                    if clamped > oldCount {
                        let lastFreq = rightState.userEQ.bands[oldCount - 1].frequency
                        let maxFreq: Float = 26000
                        let newBandCount = clamped - oldCount
                        let ratio = pow(maxFreq / lastFreq, 1 / Float(newBandCount + 1))

                        for i in oldCount..<clamped {
                            let freq = lastFreq * pow(ratio, Float(i - oldCount + 1))
                            rightState.userEQ.bands[i] = EQBandConfiguration.parametric(
                                frequency: freq,
                                q: EQConfiguration.defaultQ
                            )
                        }
                    }
                } else {
                    let frequencies = EQConfiguration.frequenciesForBandCount(clamped)
                    for (index, frequency) in frequencies.enumerated() {
                        rightState.userEQ.bands[index] = EQBandConfiguration.parametric(
                            frequency: frequency,
                            q: EQConfiguration.defaultQ
                        )
                    }
                }
                rightState.userEQ.activeBandCount = clamped
            }

            // Update published property to max of both
            activeBandCount = max(leftState.userEQ.activeBandCount, rightState.userEQ.activeBandCount)
        }

        return clamped
    }

    /// Sets the number of active bands for a specific channel (used by preset loading).
    /// In linked mode, this sets both channels. In stereo mode, sets only the specified channel.
    func setActiveBandCount(_ newValue: Int, channel: ChannelFocus) {
        let clamped = EQConfiguration.clampBandCount(newValue)

        switch channelMode {
        case .linked:
            // Linked mode: set both channels
            leftState.userEQ.activeBandCount = clamped
            rightState.userEQ.activeBandCount = clamped
        case .stereo:
            // Stereo mode: set only the specified channel
            switch channel {
            case .left:
                leftState.userEQ.activeBandCount = clamped
            case .right:
                rightState.userEQ.activeBandCount = clamped
            }
        }

        switch channelMode {
        case .linked:
            activeBandCount = leftState.userEQ.activeBandCount
        case .stereo:
            activeBandCount = max(leftState.userEQ.activeBandCount, rightState.userEQ.activeBandCount)
        }
    }

    /// Checks if any bands up to the given count have been modified (non-zero gain).
    private func hasModifiedBands(upTo count: Int) -> Bool {
        for i in 0..<count {
            if bands[i].gain != 0 { return true }
        }
        return false
    }

    /// Checks if any bands up to the given count have been modified (non-zero gain) for a specific channel.
    private func hasModifiedBands(upTo count: Int, channel: ChannelFocus) -> Bool {
        let targetBands = channel == .left ? leftState.userEQ.bands : rightState.userEQ.bands
        for i in 0..<count {
            if targetBands[i].gain != 0 { return true }
        }
        return false
    }

    /// Resets all bands with proper frequency spreading across the spectrum.
    func resetBandsWithFrequencySpread() {
        let frequencies = EQConfiguration.frequenciesForBandCount(activeBandCount)
        for (index, frequency) in frequencies.enumerated() {
            let band = EQBandConfiguration.parametric(
                frequency: frequency,
                q: EQConfiguration.defaultQ
            )
            leftState.userEQ.bands[index] = band
            rightState.userEQ.bands[index] = band
        }
    }

    static func clampBandCount(_ value: Int) -> Int {
        min(max(1, value), maxBandCount)
    }

    // MARK: - Default Frequencies

    /// Generates frequencies for a specific band count.
    /// For 10 bands, uses standard musical frequencies: 32, 64, 128, 256, 512, 1000, 2000, 4000, 8000, 16000
    /// For other counts, uses logarithmic spacing from 20Hz to 26000Hz.
    nonisolated static func frequenciesForBandCount(_ count: Int) -> [Float] {
        // Standard 10-band EQ frequencies (powers of 2, centered around 1kHz)
        if count == 10 {
            return [32, 64, 128, 256, 512, 1000, 2000, 4000, 8000, 16000]
        }

        // Logarithmic spacing for other band counts
        let minFrequency: Float = 20
        let maxFrequency: Float = 26000
        let steps = max(count - 1, 1)
        let ratio = pow(maxFrequency / minFrequency, 1 / Float(steps))

        return (0..<count).map { index in
            minFrequency * pow(ratio, Float(index))
        }
    }

    /// Generates logarithmically spaced default frequencies for all 64 bands.
    nonisolated private static func defaultFrequencies() -> [Float] {
        frequenciesForBandCount(maxBandCount)
    }

    /// Generates default band configurations for all bands.
    nonisolated static func defaultBands() -> [EQBandConfiguration] {
        defaultFrequencies().map { frequency in
            EQBandConfiguration.parametric(
                frequency: frequency,
                q: defaultQ
            )
        }
    }

    // MARK: - Channel Mode Management

    /// Sets the channel mode.
    /// When switching from linked to stereo, copies left channel state to right.
    /// When switching from stereo to linked, copies left channel state to right ("L always wins").
    func setChannelMode(_ newMode: ChannelMode) {
        guard newMode != channelMode else { return }

        if newMode == .stereo && channelMode == .linked {
            // Copy left state to right when switching to stereo
            rightState = leftState
        } else if newMode == .linked && channelMode == .stereo {
            // Copy left state to right when switching to linked ("L always wins")
            rightState = leftState
        }

        channelMode = newMode

        // Update activeBandCount to reflect the mode change
        switch channelMode {
        case .linked:
            activeBandCount = leftState.userEQ.activeBandCount
        case .stereo:
            activeBandCount = max(leftState.userEQ.activeBandCount, rightState.userEQ.activeBandCount)
        }

        objectWillChange.send()
    }

    // MARK: - Band Updates

    private func isValidIndex(_ index: Int) -> Bool {
        index >= 0 && index < EQConfiguration.maxBandCount
    }

    /// Updates the gain for a specific band.
    /// In linked mode, updates both channels.
    /// In stereo mode, updates only the currently edited channel.
    func updateBandGain(index: Int, gain: Float) {
        guard isValidIndex(index) else { return }

        if channelMode == .linked {
            leftState.userEQ.bands[index].gain = gain
            rightState.userEQ.bands[index].gain = gain
        } else {
            if channelFocus == .left {
                leftState.userEQ.bands[index].gain = gain
            } else {
                rightState.userEQ.bands[index].gain = gain
            }
        }
        objectWillChange.send()
    }

    /// Updates the gain for a specific band on a specific channel.
    func updateBandGain(index: Int, gain: Float, channel: EQChannelTarget) {
        guard isValidIndex(index) else { return }

        let targetChannel = channelMode == .linked ? .both : channel

        if targetChannel == .both || targetChannel == .left {
            leftState.userEQ.bands[index].gain = gain
        }
        if targetChannel == .both || targetChannel == .right {
            rightState.userEQ.bands[index].gain = gain
        }
        objectWillChange.send()
    }

    /// Updates the Q factor for a specific band.
    func updateBandQ(index: Int, q: Float) {
        guard isValidIndex(index) else { return }

        if channelMode == .linked {
            leftState.userEQ.bands[index].q = q
            rightState.userEQ.bands[index].q = q
        } else {
            if channelFocus == .left {
                leftState.userEQ.bands[index].q = q
            } else {
                rightState.userEQ.bands[index].q = q
            }
        }
        objectWillChange.send()
    }

    /// Updates the Q factor for a specific band on a specific channel.
    func updateBandQ(index: Int, q: Float, channel: EQChannelTarget) {
        guard isValidIndex(index) else { return }

        let targetChannel = channelMode == .linked ? .both : channel

        if targetChannel == .both || targetChannel == .left {
            leftState.userEQ.bands[index].q = q
        }
        if targetChannel == .both || targetChannel == .right {
            rightState.userEQ.bands[index].q = q
        }
        objectWillChange.send()
    }

    /// Updates the frequency for a specific band.
    func updateBandFrequency(index: Int, frequency: Float) {
        guard isValidIndex(index) else { return }

        if channelMode == .linked {
            leftState.userEQ.bands[index].frequency = frequency
            rightState.userEQ.bands[index].frequency = frequency
        } else {
            if channelFocus == .left {
                leftState.userEQ.bands[index].frequency = frequency
            } else {
                rightState.userEQ.bands[index].frequency = frequency
            }
        }
        objectWillChange.send()
    }

    /// Updates the frequency for a specific band on a specific channel.
    func updateBandFrequency(index: Int, frequency: Float, channel: EQChannelTarget) {
        guard isValidIndex(index) else { return }

        let targetChannel = channelMode == .linked ? .both : channel

        if targetChannel == .both || targetChannel == .left {
            leftState.userEQ.bands[index].frequency = frequency
        }
        if targetChannel == .both || targetChannel == .right {
            rightState.userEQ.bands[index].frequency = frequency
        }
        objectWillChange.send()
    }

    /// Updates the bypass state for a specific band.
    func updateBandBypass(index: Int, bypass: Bool) {
        guard isValidIndex(index) else { return }

        if channelMode == .linked {
            leftState.userEQ.bands[index].bypass = bypass
            rightState.userEQ.bands[index].bypass = bypass
        } else {
            if channelFocus == .left {
                leftState.userEQ.bands[index].bypass = bypass
            } else {
                rightState.userEQ.bands[index].bypass = bypass
            }
        }
        objectWillChange.send()
    }

    /// Updates the bypass state for a specific band on a specific channel.
    func updateBandBypass(index: Int, bypass: Bool, channel: EQChannelTarget) {
        guard isValidIndex(index) else { return }

        let targetChannel = channelMode == .linked ? .both : channel

        if targetChannel == .both || targetChannel == .left {
            leftState.userEQ.bands[index].bypass = bypass
        }
        if targetChannel == .both || targetChannel == .right {
            rightState.userEQ.bands[index].bypass = bypass
        }
        objectWillChange.send()
    }

    /// Updates the filter type for a specific band.
    func updateBandFilterType(index: Int, filterType: FilterType) {
        guard isValidIndex(index) else { return }

        if channelMode == .linked {
            leftState.userEQ.bands[index].filterType = filterType
            rightState.userEQ.bands[index].filterType = filterType
        } else {
            if channelFocus == .left {
                leftState.userEQ.bands[index].filterType = filterType
            } else {
                rightState.userEQ.bands[index].filterType = filterType
            }
        }
        objectWillChange.send()
    }

    /// Updates the filter type for a specific band on a specific channel.
    func updateBandFilterType(index: Int, filterType: FilterType, channel: EQChannelTarget) {
        guard isValidIndex(index) else { return }

        let targetChannel = channelMode == .linked ? .both : channel

        if targetChannel == .both || targetChannel == .left {
            leftState.userEQ.bands[index].filterType = filterType
        }
        if targetChannel == .both || targetChannel == .right {
            rightState.userEQ.bands[index].filterType = filterType
        }
        objectWillChange.send()
    }
}
