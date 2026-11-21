// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Combine
import CoreAudio
import Foundation
import os.log

/// Errors surfaced by correction actions in the UI.
enum CorrectionError: LocalizedError {
    case noOutputDeviceSelected

    var errorDescription: String? {
        switch self {
        case .noOutputDeviceSelected:
            return "No output device is selected. Start routing and select an output device first."
        }
    }
}

/// Owns the correction layer (layer 1): the active output device's
/// correction profile, preference trims, and loudness shelves,
/// composed by `CorrectionComposer`, designed by the coefficient
/// stager's one designer, and staged alongside the user EQ.
///
/// Recomposition triggers: output device change (profile recall and
/// volume observation move to the new device), output volume change
/// (loudness shelves track the listening level), pipeline reapply
/// (via `AudioRoutingCoordinator.reapplyConfiguration`), and any
/// profile/trim/loudness edit.
///
/// The correction layer also owns its headroom: the correction preamp
/// is the more protective of the profile's published preamp and the
/// exact composite-peak analysis of the composed layer, so correction
/// boosts cannot clip the input stage either.
@MainActor
final class CorrectionController: ObservableObject {
    @Published var enabled = true { didSet { refresh() } }

    /// Profile bound to the current output device, if one exists.
    @Published private(set) var activeProfile: DeviceCorrectionProfile?

    /// Display name of the current output device.
    @Published private(set) var currentDeviceName: String?

    /// UID of the current output device.
    @Published private(set) var currentDeviceUID: String?

    /// Correction being previewed (A1): parsed but not saved. While a
    /// preview is audible, `refresh()` composes it instead of the
    /// device's saved profile. The store is written only by
    /// `commitPreview()`, so cancelling restores the exact prior
    /// sound by construction — there is no restore routine to get
    /// wrong. Preview state is memory-only: quitting mid-preview
    /// simply never saved anything.
    @Published private(set) var previewProfile: DeviceCorrectionProfile?

    /// Parser warnings from the previewed import, for display.
    @Published private(set) var previewWarnings: [String] = []

    /// True while the preview, not the saved correction, is heard.
    @Published private(set) var previewAudible = false

    /// BS.1770 paired loudness delta of the current render (post −
    /// pre, dB), wired by the owner. Used only to level-match the
    /// preview against the saved sound; nil when unavailable.
    var loudnessDeltaProvider: (() -> Double?)?

    private let eqConfiguration: EQConfiguration
    private let routingCoordinator: AudioRoutingCoordinator
    private let volumeService: VolumeControlling
    private let deviceProvider: DeviceProviding
    private let profileStore: DeviceCorrectionStore
    private let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "CorrectionController")

    private var cancellables = Set<AnyCancellable>()
    private var observedVolumeDeviceID: AudioDeviceID?
    @Published private(set) var currentVolumeScalar: Float?
    private var lastRefreshAt = Date.distantPast
    private var trailingRefreshTask: Task<Void, Never>?

    /// Meter delta of the saved sound, captured when a preview
    /// begins; the reference the preview is matched against. Kept
    /// across preview→preview replacement (the reference is always
    /// the saved state, never another preview).
    private var previewReferenceDeltaDB: Double?
    /// Broadband offset (dB) currently folded into the preview's
    /// preamp for level matching; set by the settle, never saved.
    private var previewMatchOffsetDB: Float = 0
    /// Bumped on every preview transition; a settle that wakes to a
    /// different generation does nothing.
    private var previewGeneration = 0
    private var previewSettleTask: Task<Void, Never>?

    init(
        eqConfiguration: EQConfiguration,
        routingCoordinator: AudioRoutingCoordinator,
        volumeService: VolumeControlling,
        deviceProvider: DeviceProviding,
        profileStore: DeviceCorrectionStore = DeviceCorrectionStore()
    ) {
        self.eqConfiguration = eqConfiguration
        self.routingCoordinator = routingCoordinator
        self.volumeService = volumeService
        self.deviceProvider = deviceProvider
        self.profileStore = profileStore
    }

    // MARK: - Lifecycle

    /// Subscribes to output device changes and applies the current
    /// device's correction. Call once, after routing exists.
    func start() {
        routingCoordinator.$selectedOutputDeviceID
            .removeDuplicates()
            .sink { [weak self] uid in
                self?.deviceChanged(uid)
            }
            .store(in: &cancellables)
        deviceChanged(routingCoordinator.selectedOutputDeviceID)
    }

    // MARK: - Composition

    /// Recomposes the correction layer from the current inputs and
    /// restages it. Cheap enough for settings edits; volume-driven
    /// calls go through `throttledRefresh` instead.
    func refresh() {
        lastRefreshAt = Date()
        activeProfile = currentDeviceUID.flatMap { profileStore.profile(forUID: $0) }

        // An audible preview composes in place of the saved profile;
        // the saved profile itself is never modified by a preview.
        let composingProfile = (previewAudible ? previewProfile : nil) ?? activeProfile

        let bands = CorrectionComposer.composeBands(
            profile: enabled ? composingProfile : nil,
            loudnessEnabled: eqConfiguration.loudnessEnabled,
            volumeScalar: currentVolumeScalar,
            loudnessStrength: eqConfiguration.loudnessStrength
        )

        let stager = routingCoordinator.eqStager
        let coefficients = stager.designedCoefficients(for: bands, count: bands.count)
        let bypassFlags = bands.map { $0.bypass }

        let analyserPreamp = HeadroomAnalyzer.recommendedAutoPreampDB(
            svfCoefficients: coefficients,
            bypassFlags: bypassFlags,
            activeBandCount: bands.count,
            sampleRate: stager.sampleRate
        )
        // The preview's preamp carries the level-match offset while
        // it is heard (ceilinged at 0 dB by PreviewMatchTracker, and
        // the headroom analysis below can still overrule it with a
        // more protective value). A saved profile's preamp is used
        // exactly as published.
        let profilePreamp: Float
        if enabled, previewAudible, let preview = previewProfile {
            profilePreamp = PreviewMatchTracker.matchedPreampDB(
                publishedPreampDB: preview.preampDB * preview.blendFactor,
                offsetDB: Double(previewMatchOffsetDB)
            )
        } else {
            // C3: the published preamp offsets the profile's own
            // boost, which the blend scales — so it scales too.
            // The analyser above still overrules when the composed
            // bands need more protection.
            profilePreamp = enabled ? (composingProfile?.preampDB ?? 0) * (composingProfile?.blendFactor ?? 1) : 0
        }
        let vector = HeadroomAnalyzer.compositeMagnitudeDBVector(
            svfCoefficients: coefficients,
            bypassFlags: bypassFlags,
            activeBandCount: bands.count,
            sampleRate: stager.sampleRate
        )
        let channelData = EQConfiguration.CascadeLayerData.ChannelData(
            coefficients: coefficients,
            bypassFlags: bypassFlags,
            activeBandCount: bands.count,
            candidateFrequencies: bands.map { Double($0.frequency) },
            magnitudeDB: vector
        )

        let previousEffective = eqConfiguration.effectiveInputGainDB
        eqConfiguration.updateCorrectionCascade(
            EQConfiguration.CascadeLayerData(
                channels: bands.isEmpty ? [] : [channelData],
                recommendedPreampDB: analyserPreamp,
                sampleRate: stager.sampleRate
            ),
            profilePreampDB: profilePreamp
        )
        if eqConfiguration.effectiveInputGainDB != previousEffective {
            routingCoordinator.updateInputGain(
                linear: AudioMath.dbToLinear(eqConfiguration.effectiveInputGainDB)
            )
        }

        routingCoordinator.pipelineManager.renderPipeline?.stageFullEQUpdate(
            channel: .both,
            layerIndex: EQLayerConstants.correctionLayerIndex,
            coefficients: coefficients,
            bypassFlags: bypassFlags,
            activeBandCount: bands.count,
            layerBypass: eqConfiguration.globalBypass
        )
    }

    // MARK: - Actions

    /// Begins a preview of an AutoEq parametric file for the current
    /// device: the correction is composed and heard, but not saved.
    /// Returns any parser warnings for display. Beginning a second
    /// preview replaces the first; the level-match reference stays
    /// the saved sound captured by the first.
    @discardableResult
    func beginAutoEqPreview(url: URL) throws -> [String] {
        guard let uid = currentDeviceUID else {
            throw CorrectionError.noOutputDeviceSelected
        }
        let result = try AutoEqImporter.importProfile(
            from: url,
            deviceUID: uid,
            deviceName: currentDeviceName ?? "Output Device"
        )
        return beginPreview(result)
    }

    /// Begins a preview of an already-parsed correction (A7: an
    /// OPRA preset chosen in the catalog picker). Same road in as
    /// AutoEq: composed and heard, not saved, until Import.
    @discardableResult
    func beginPreview(_ result: AutoEqImportResult, initialBlendPercent: Double = 70) -> [String] {
        if previewProfile == nil {
            previewReferenceDeltaDB = loudnessDeltaProvider?() ?? nil
        }
        previewGeneration += 1
        previewMatchOffsetDB = 0
        // C3: a new correction starts at 70% blend — the gentler
        // first hearing; the slider in the preview block raises
        // it to the full correction, and Import commits the set
        // value. D6: the speaker guard passes 100 — a guard is
        // not a taste and does not stage gently.
        var staged = result.profile
        staged.blendPercent = initialBlendPercent
        previewProfile = staged
        previewWarnings = result.warnings
        previewAudible = true
        refresh()
        schedulePreviewSettle()
        return result.warnings
    }

    /// Saves the previewed profile as the device's correction,
    /// exactly as published (the match offset was a comparison aid
    /// and is never baked in), and ends the preview.
    func commitPreview() {
        guard let preview = previewProfile else { return }
        endPreview()
        profileStore.save(preview)
        refresh()
    }

    /// Ends the preview without saving. The saved profile was never
    /// touched, so recomposing it restores the exact prior sound.
    func cancelPreview() {
        guard previewProfile != nil else { return }
        endPreview()
        refresh()
    }

    /// Switches what is heard during a preview: the preview itself,
    /// or the device's saved correction (the reference).
    func setPreviewAudible(_ audible: Bool) {
        guard previewProfile != nil, previewAudible != audible else { return }
        previewAudible = audible
        previewGeneration += 1
        if audible {
            schedulePreviewSettle()
        } else {
            previewSettleTask?.cancel()
        }
        refresh()
    }

    private func endPreview() {
        previewGeneration += 1
        previewSettleTask?.cancel()
        previewSettleTask = nil
        previewProfile = nil
        previewWarnings = []
        previewAudible = false
        previewReferenceDeltaDB = nil
        previewMatchOffsetDB = 0
    }

    /// Level matching, one settle per entry into the audible
    /// preview: the paired delta needs a few seconds of programme
    /// under the preview before it describes the preview, so the
    /// offset is computed once, ~4 s in, from the delta the meter
    /// has converged to by then. The delta read back already
    /// includes any offset in force, so it is subtracted back out
    /// first — repeated settles are idempotent, not a feedback loop.
    private func schedulePreviewSettle() {
        previewSettleTask?.cancel()
        guard previewReferenceDeltaDB != nil else { return }
        let generation = previewGeneration
        previewSettleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            guard let self,
                  generation == self.previewGeneration,
                  self.previewAudible,
                  self.previewProfile != nil,
                  let reference = self.previewReferenceDeltaDB,
                  let current = self.loudnessDeltaProvider?() ?? nil
            else { return }
            let unmatchedCurrent = current + Double(self.previewMatchOffsetDB)
            let offset = PreviewMatchTracker.offsetDB(
                referenceDeltaDB: reference,
                currentDeltaDB: unmatchedCurrent
            )
            if abs(offset - Double(self.previewMatchOffsetDB)) > 0.05 {
                self.previewMatchOffsetDB = Float(offset)
                self.refresh()
            }
        }
    }

    /// Snapshots the current user EQ as the current device's
    /// correction profile (left channel; the linked-mode reference).
    func useCurrentEQAsCorrection() throws {
        guard let uid = currentDeviceUID else {
            throw CorrectionError.noOutputDeviceSelected
        }
        let userLayer = eqConfiguration.leftState.userEQ
        let bands = userLayer.bands.prefix(userLayer.activeBandCount).map { band in
            PresetBand(
                frequency: band.frequency, q: band.q, gain: band.gain,
                filterType: band.filterType, bypass: band.bypass
            )
        }
        let profile = DeviceCorrectionProfile(
            deviceUID: uid,
            deviceName: currentDeviceName ?? "Output Device",
            sourceName: "Current EQ (copied)",
            preampDB: 0,
            bands: Array(bands)
        )
        profileStore.save(profile)
        refresh()
    }

    /// Removes the current device's profile. Loudness shelves, if
    /// enabled, are unaffected (they are not part of the profile).
    func clearCorrection() {
        guard let uid = currentDeviceUID else { return }
        if previewProfile != nil { endPreview() }
        profileStore.remove(forUID: uid)
        refresh()
    }

    /// Preference trims route by state (A2): during a preview they
    /// shape the preview in memory only — no store write, so Cancel
    /// stays exact — and otherwise they edit the saved profile. The
    /// bass range follows the preference data (Olive's 249 listeners:
    /// the middle 90% chose +0.8…+12.6 dB of bass), so bass runs
    /// −10…+12; treble stays ±10 for lack of equivalent data.
    func setBassTrim(_ db: Float) {
        let clamped = min(max(db, -10), 12)
        if previewProfile != nil {
            previewProfile?.bassTrimDB = clamped
            refresh()
        } else {
            mutateActiveProfile { $0.bassTrimDB = clamped }
        }
    }

    /// Correction blend (C3), routed exactly like the trims:
    /// preview edits live in memory only, saved edits persist.
    func setBlendPercent(_ percent: Double) {
        let clamped = min(max(percent, 0), 100)
        if previewProfile != nil {
            previewProfile?.blendPercent = clamped
            refresh()
        } else {
            mutateActiveProfile { $0.blendPercent = clamped }
        }
    }

    func setTrebleTrim(_ db: Float) {
        let clamped = min(max(db, -10), 10)
        if previewProfile != nil {
            previewProfile?.trebleTrimDB = clamped
            refresh()
        } else {
            mutateActiveProfile { $0.trebleTrimDB = clamped }
        }
    }

    private func mutateActiveProfile(_ change: (inout DeviceCorrectionProfile) -> Void) {
        guard var profile = activeProfile else { return }
        change(&profile)
        profileStore.save(profile)
        refresh()
    }

    // MARK: - Device and Volume Tracking

    private func deviceChanged(_ uid: String?) {
        // A preview belongs to the device and saved state it started
        // on; a device change ends it (unsaved) rather than stranding
        // the preview layer on the new device.
        if previewProfile != nil { endPreview() }
        currentDeviceUID = uid
        currentDeviceName = uid.flatMap { deviceProvider.device(forUID: $0)?.name }
        observeVolume(for: uid)
        refresh()
    }

    private func observeVolume(for uid: String?) {
        if let previous = observedVolumeDeviceID {
            volumeService.stopObservingDeviceVolumeChanges(deviceID: previous)
            observedVolumeDeviceID = nil
        }
        currentVolumeScalar = nil
        guard let uid, let deviceID = deviceProvider.deviceID(forUID: uid) else { return }
        observedVolumeDeviceID = deviceID
        currentVolumeScalar = volumeService.getDeviceVolumeScalar(deviceID: deviceID)
        volumeService.observeDeviceVolumeChanges(deviceID: deviceID) { [weak self] newVolume in
            Task { @MainActor in
                self?.volumeChanged(newVolume)
            }
        }
    }

    private func volumeChanged(_ newVolume: Float) {
        currentVolumeScalar = newVolume
        throttledRefresh()
    }

    /// Volume drags fire dozens of events per second; recompose at
    /// most every 60 ms, with one trailing call so the final resting
    /// volume is always the one staged.
    private func throttledRefresh() {
        if Date().timeIntervalSince(lastRefreshAt) >= 0.06 {
            trailingRefreshTask?.cancel()
            refresh()
            return
        }
        guard trailingRefreshTask == nil else { return }
        trailingRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 70_000_000)
            guard !Task.isCancelled else { return }
            self?.trailingRefreshTask = nil
            self?.refresh()
        }
    }
}
