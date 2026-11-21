import Foundation

/// Parameter interpolation, not a claim of linear response interpolation.
enum PresetBlend {
    static func bands(from source: [EQBandConfiguration], to target: [PresetBand], amount: Float) -> [EQBandConfiguration] {
        let count = min(EQConfiguration.maxBandCount, max(source.count, target.count))
        return (0..<count).map { i in
            let old = i < source.count ? source[i] : EQBandConfiguration(
                frequency: target[i].frequency, q: target[i].q, gain: 0,
                filterType: target[i].filterType, bypass: false)
            let new = i < target.count ? target[i].toEQBandConfiguration() : EQBandConfiguration(
                frequency: old.frequency, q: old.q, gain: 0, filterType: old.filterType, bypass: false)
            let frequency = exp(log(max(20, old.frequency)) * (1 - amount) + log(max(20, new.frequency)) * amount)
            return EQBandConfiguration(frequency: AudioConstants.clampFrequency(frequency),
                q: BandwidthConverter.clampQ(old.q + (new.q - old.q) * amount),
                gain: AudioConstants.clampGain(old.gain + (new.gain - old.gain) * amount),
                filterType: amount < 0.5 ? old.filterType : new.filterType,
                bypass: amount < 0.5 ? old.bypass : new.bypass)
        }
    }
}

@MainActor
extension EqumaczerStore {
    /// Every preview is derived from the immutable baseline, never the last preview.
    func previewBlend(preset: Preset, amount: Double, from baseline: SoundState) {
        guard amount.isFinite else { return }
        let t = Float(min(1, max(0, amount)))
        if t == 0 { restoreSoundState(baseline); return }
        if t == 1 {
            presetManager.applyPreset(preset, to: eqConfiguration)
            inputGain = preset.settings.inputGain
            outputGain = preset.settings.outputGain
            isBypassed = preset.settings.globalBypass
        } else {
            let left = PresetBlend.bands(from: Array(baseline.shape.leftBands.prefix(baseline.shape.leftCount)),
                to: preset.settings.leftBands, amount: t)
            let targetRight = preset.settings.channelMode == "linked" ? preset.settings.leftBands : preset.settings.rightBands
            let right = PresetBlend.bands(from: Array(baseline.shape.rightBands.prefix(baseline.shape.rightCount)),
                to: targetRight, amount: t)
            let mode: ChannelMode = baseline.shape.channelMode == .stereo || preset.settings.channelMode == "stereo" ? .stereo : .linked
            SoundCapture(leftBands: left, rightBands: right, leftCount: left.count,
                         rightCount: right.count, channelMode: mode).restore(to: eqConfiguration)
            inputGain = baseline.inputGain + (preset.settings.inputGain - baseline.inputGain) * t
            outputGain = baseline.outputGain + (preset.settings.outputGain - baseline.outputGain) * t
            isBypassed = t < 0.5 ? baseline.bypass : preset.settings.globalBypass
        }
        channelFocus = baseline.focus
        routingCoordinator.reapplyConfiguration()
        presetManager.markAsModified()
    }
}
