import Foundation

/// Immutable restore point for one user action, including editing context.
struct SoundState {
    let shape: SoundCapture
    let inputGain: Float
    let outputGain: Float
    let bypass: Bool
    let focus: ChannelFocus
    let presetName: String?
    let presetModified: Bool
}

@MainActor
extension EqumaczerStore {
    func updateBandShape(index: Int, frequency: Float, gain: Float) {
        eqConfiguration.updateBandFrequency(index: index, frequency: AudioConstants.clampFrequency(frequency))
        eqConfiguration.updateBandGain(index: index, gain: AudioConstants.clampGain(gain))
        routingCoordinator.updateBandGain(index: index)
        presetManager.markAsModified()
    }

    func captureSoundState() -> SoundState {
        SoundState(shape: .capture(from: eqConfiguration), inputGain: inputGain,
                   outputGain: outputGain, bypass: isBypassed, focus: channelFocus,
                   presetName: presetManager.selectedPresetName, presetModified: presetManager.isModified)
    }

    func restoreSoundState(_ state: SoundState) {
        state.shape.restore(to: eqConfiguration)
        channelFocus = state.focus
        inputGain = state.inputGain
        outputGain = state.outputGain
        isBypassed = state.bypass
        routingCoordinator.reapplyConfiguration()
        presetManager.restoreSelection(named: state.presetName, modified: state.presetModified)
    }

    func registerSoundUndo(label: String, state: SoundState) {
        let after = captureSoundState()
        registerUndo(label: label, redo: { [weak self] in
            guard let self else { return false }
            self.restoreSoundState(after)
            return true
        }) { [weak self] in
            guard let self else { return false }
            self.restoreSoundState(state)
            self.clearFlattenReceipt()
            return true
        }
    }

    /// Model mutation, audio commit, modified state and Undo share one boundary.
    func performSoundChange(label: String, _ change: (EQConfiguration) -> Void) {
        let before = captureSoundState()
        change(eqConfiguration)
        routingCoordinator.reapplyConfiguration()
        presetManager.markAsModified()
        registerSoundUndo(label: label, state: before)
    }

    func applySoundCapture(_ capture: SoundCapture, label: String) {
        performSoundChange(label: label) { capture.restore(to: $0) }
    }
}
