// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// C2: drives a blind A/B test against the live store.
///
/// Two sources share the session. A preset test captures the
/// current configuration (the Flatten-undo pattern: both
/// channels' bands, counts, channel mode), applies the candidate
/// with `loadPreset`, and level-matches from the live BS.1770
/// delta each side earns while it plays — the candidate side
/// carries a trim of −(Δcandidate − Δcurrent), clamped to ±6 dB,
/// through the configuration's blind-trim term. A correction test
/// needs no trim: A1's preview already matches candidate to
/// current continuously, so the controller only drives
/// `setPreviewAudible` blind and lets the pick commit or cancel.
///
/// No scores, no history: when the sheet closes, nothing about
/// the test remains anywhere.
@MainActor
final class BlindABController: ObservableObject {
    @Published private(set) var session: BlindABSession.State?
    @Published private(set) var candidateName: String?
    /// Whether both sides' loudness has been measured (preset mode).
    @Published private(set) var levelsMatched = false

    private enum Mode {
        case preset
        case correction
    }

    private let store: EqumaczerStore
    private let correctionController: CorrectionController
    private var mode: Mode?
    private var captured: SoundCapture?
    private var candidatePreset: Preset?
    private var timer: Timer?
    private var sideShownAt = Date()
    private var candidateDelta: Double?
    private var currentDelta: Double?

    init(store: EqumaczerStore, correctionController: CorrectionController) {
        self.store = store
        self.correctionController = correctionController
    }

    // MARK: - Starting

    func startPresetTest(_ preset: Preset) {
        captured = SoundCapture.capture(from: store.eqConfiguration)
        candidatePreset = preset
        candidateName = preset.metadata.name
        mode = .preset
        candidateDelta = nil
        currentDelta = nil
        levelsMatched = false
        beginSession()
    }

    func startCorrectionTest() {
        guard let preview = correctionController.previewProfile else { return }
        candidateName = preview.sourceName
        mode = .correction
        levelsMatched = true // A1's preview match is continuous.
        beginSession()
    }

    private func beginSession() {
        session = BlindABSession.State(candidateIsA: Bool.random())
        sideShownAt = Date()
        applySide(.a)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleDelta() }
        }
    }

    // MARK: - Auditioning

    func showSide(_ letter: BlindABSession.Letter) {
        guard var state = session, state.phase == .listening else { return }
        state.show(letter)
        session = state
        sideShownAt = Date()
        applySide(letter)
        refreshTrim()
    }

    private func applySide(_ letter: BlindABSession.Letter) {
        guard let state = session else { return }
        let candidate = state.isCandidate(letter)
        switch mode {
        case .preset:
            if candidate, let preset = candidatePreset {
                store.loadPreset(preset)
            } else {
                restoreCapture()
            }
        case .correction:
            correctionController.setPreviewAudible(candidate)
        case nil:
            break
        }
    }

    // MARK: - Level matching (preset mode)

    private func sampleDelta() {
        guard mode == .preset,
              let state = session, state.phase == .listening,
              Date().timeIntervalSince(sideShownAt) > 2.5,
              let delta = store.meterStore.loudnessMeter.bypassDeltaDB
        else { return }
        if state.isCandidate(state.current) {
            candidateDelta = delta
        } else {
            currentDelta = delta
        }
        levelsMatched = candidateDelta != nil && currentDelta != nil
        refreshTrim()
    }

    private func refreshTrim() {
        guard mode == .preset, let state = session else { return }
        if state.isCandidate(state.current),
           let candidate = candidateDelta, let current = currentDelta {
            let trim = max(-6.0, min(6.0, -(candidate - current)))
            store.eqConfiguration.setBlindTrimDB(Float(trim))
        } else {
            store.eqConfiguration.setBlindTrimDB(0)
        }
    }

    // MARK: - Picking and finishing

    func pick(_ letter: BlindABSession.Letter) {
        guard var state = session else { return }
        state.pick(letter)
        guard case .revealed(let winnerIsCandidate) = state.phase else { return }
        session = state
        timer?.invalidate()
        store.eqConfiguration.setBlindTrimDB(0)
        finish(winnerIsCandidate: winnerIsCandidate)
    }

    /// After the reveal, switch the final sound to the other side.
    func useOtherSide() {
        guard let state = session,
              case .revealed(let winnerIsCandidate) = state.phase else { return }
        finish(winnerIsCandidate: !winnerIsCandidate)
    }

    private func finish(winnerIsCandidate: Bool) {
        switch mode {
        case .preset:
            if winnerIsCandidate, let preset = candidatePreset {
                store.loadPreset(preset)
            } else {
                restoreCapture()
            }
        case .correction:
            if winnerIsCandidate {
                correctionController.commitPreview()
            } else {
                correctionController.cancelPreview()
            }
        case nil:
            break
        }
    }

    /// Abandon the test: presets restore the pre-test sound; a
    /// correction preview stays staged but inaudible.
    func cancel() {
        guard session != nil else { return }
        timer?.invalidate()
        store.eqConfiguration.setBlindTrimDB(0)
        switch mode {
        case .preset:
            restoreCapture()
        case .correction:
            correctionController.setPreviewAudible(false)
        case nil:
            break
        }
        session = nil
    }

    /// Sheet dismissed. A test still listening is a cancel; a
    /// revealed test has already applied its outcome.
    func end() {
        if let state = session, state.phase == .listening {
            cancel()
        } else {
            timer?.invalidate()
            store.eqConfiguration.setBlindTrimDB(0)
            session = nil
        }
    }

    // MARK: - Capture / restore

    private func restoreCapture() {
        guard let captured else { return }
        captured.restore(to: store.eqConfiguration)
        store.routingCoordinator.reapplyConfiguration()
        store.presetManager.markAsModified()
    }
}
