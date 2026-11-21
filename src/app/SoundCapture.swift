// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// A restorable snapshot of the manual EQ's shape: both
/// channels' bands, their active counts, and the channel mode.
/// First built for C2's blind test (capture the listener's sound
/// before auditioning a candidate); extracted in C4 so the
/// store's undo stack restores through the same code path —
/// one implementation of "put the sound back".
struct SoundCapture {
    var leftBands: [EQBandConfiguration]
    var rightBands: [EQBandConfiguration]
    var leftCount: Int
    var rightCount: Int
    var channelMode: ChannelMode

    @MainActor
    static func capture(from config: EQConfiguration) -> SoundCapture {
        SoundCapture(
            leftBands: config.leftState.userEQ.bands,
            rightBands: config.rightState.userEQ.bands,
            leftCount: config.leftState.userEQ.activeBandCount,
            rightCount: config.rightState.userEQ.activeBandCount,
            channelMode: config.channelMode
        )
    }

    /// Writes the snapshot back through the per-band updaters —
    /// the same path presets apply through.
    @MainActor
    func restore(to config: EQConfiguration) {
        config.setChannelMode(channelMode)
        switch channelMode {
        case .linked:
            _ = config.setActiveBandCount(leftCount)
            for (index, band) in leftBands.enumerated() {
                config.updateBandFrequency(index: index, frequency: band.frequency)
                config.updateBandQ(index: index, q: band.q)
                config.updateBandGain(index: index, gain: band.gain)
                config.updateBandFilterType(index: index, filterType: band.filterType)
                config.updateBandBypass(index: index, bypass: band.bypass)
            }
        case .stereo:
            config.setActiveBandCount(leftCount, channel: .left)
            config.setActiveBandCount(rightCount, channel: .right)
            for (index, band) in leftBands.enumerated() {
                config.updateBandFrequency(index: index, frequency: band.frequency, channel: .left)
                config.updateBandQ(index: index, q: band.q, channel: .left)
                config.updateBandGain(index: index, gain: band.gain, channel: .left)
                config.updateBandFilterType(index: index, filterType: band.filterType, channel: .left)
                config.updateBandBypass(index: index, bypass: band.bypass, channel: .left)
            }
            for (index, band) in rightBands.enumerated() {
                config.updateBandFrequency(index: index, frequency: band.frequency, channel: .right)
                config.updateBandQ(index: index, q: band.q, channel: .right)
                config.updateBandGain(index: index, gain: band.gain, channel: .right)
                config.updateBandFilterType(index: index, filterType: band.filterType, channel: .right)
                config.updateBandBypass(index: index, bypass: band.bypass, channel: .right)
            }
        }
    }
}
