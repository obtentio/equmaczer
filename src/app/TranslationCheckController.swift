// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// C6: runs a translation check by borrowing the manual layer.
///
/// Starting captures the listener's bands (SoundCapture, C4),
/// appends the approximation's bands as ordinary band objects,
/// and lets the stager + auto-preamp treat them like any user
/// bands. Stopping restores the capture exactly — unless the
/// manual bands no longer end with the bands the check added
/// (a preset landed mid-check): then the current sound is a
/// state chosen after the check began, and restoring would
/// clobber it, so the check simply lets go.
@MainActor
final class TranslationCheckController: ObservableObject {
    @Published private(set) var active: TranslationCheck?

    private let store: EqumaczerStore
    private var capture: SoundCapture?
    private var appendedCount = 0

    init(store: EqumaczerStore) {
        self.store = store
    }

    func start(_ target: TranslationCheck) {
        stop()
        let config = store.eqConfiguration
        let bands = target.bands
        guard config.activeBandCount + bands.count <= EQConfiguration.maxBandCount else { return }
        capture = SoundCapture.capture(from: config)
        appendedCount = bands.count
        let base = store.bandCount
        store.bandCount = base + bands.count
        for (offset, band) in bands.enumerated() {
            let index = base + offset
            store.updateBandFrequency(index: index, frequency: AudioConstants.clampFrequency(band.frequency))
            store.updateBandQ(index: index, q: band.q)
            store.updateBandGain(index: index, gain: band.gain)
            store.updateBandFilterType(index: index, filterType: band.filterType)
            store.updateBandBypass(index: index, bypass: false)
        }
        active = target
    }

    func stop() {
        guard active != nil, let capture else {
            active = nil
            return
        }
        if manualLayerStillCarriesTheCheck(capture: capture) {
            capture.restore(to: store.eqConfiguration)
            store.routingCoordinator.reapplyConfiguration()
            store.presetManager.markAsModified()
        }
        self.capture = nil
        appendedCount = 0
        active = nil
    }

    /// The guard: the slots the check appended must still hold
    /// its bands (same count, same gains at the tail of the
    /// active bands) for a restore to be the right move.
    private func manualLayerStillCarriesTheCheck(capture: SoundCapture) -> Bool {
        let config = store.eqConfiguration
        let baseCount = (capture.channelMode == .stereo && config.channelFocus == .right)
            ? capture.rightCount
            : capture.leftCount
        guard config.channelMode == capture.channelMode,
              store.bandCount == baseCount + appendedCount,
              let target = active else { return false }
        let current = config.bands
        for (offset, band) in target.bands.enumerated() {
            let staged = current[baseCount + offset]
            guard staged.filterType == band.filterType,
                  abs(staged.gain - band.gain) < 0.01,
                  abs(staged.frequency - band.frequency) < 0.5 else { return false }
        }
        return true
    }
}
