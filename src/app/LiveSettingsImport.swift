import Foundation

@MainActor
extension EqumaczerStore {
    func importSettings(data: Data) throws {
        try importSettings(SettingsImport.decode(data))
    }

    /// Validate the entire document before changing live or persisted state.
    func importSettings(_ snapshot: AppStateSnapshot) throws {
        guard SettingsImport.isValid(snapshot) else { throw SettingsImport.ImportError.invalidSettings }
        let before = currentSnapshot
        let presetName = presetManager.selectedPresetName
        let presetModified = presetManager.isModified
        restoreSettings(snapshot)
        presetManager.markAsModified()
        let after = currentSnapshot
        registerUndo(label: "Import settings", redo: { [weak self] in
            guard let self else { return false }
            self.restoreSettings(after)
            self.presetManager.markAsModified()
            return true
        }) { [weak self] in
            guard let self else { return false }
            self.restoreSettings(before)
            self.presetManager.restoreSelection(named: presetName, modified: presetModified)
            return true
        }
    }

    private func restoreSettings(_ snapshot: AppStateSnapshot) {
        let previous = currentSnapshot
        eqConfiguration.restore(from: snapshot)
        restoreAppPreferences(from: snapshot)
        meterStore.metersEnabled = snapshot.metersEnabled
        correctionController.enabled = snapshot.correctionEnabled
        channelController.enabled = snapshot.channelEnabled
        routingCoordinator.reapplyConfiguration()
        routingCoordinator.updateInputGain(linear: AudioMath.dbToLinear(eqConfiguration.effectiveInputGainDB))
        routingCoordinator.updateOutputGain(linear: AudioMath.dbToLinear(outputGain))
        routingCoordinator.updateProcessingMode(systemEQOff: isBypassed, compareMode: compareMode)
        if previous.inputDeviceID != currentSnapshot.inputDeviceID
            || previous.outputDeviceID != currentSnapshot.outputDeviceID
            || previous.manualModeEnabled != snapshot.manualModeEnabled
            || previous.captureMode != snapshot.captureMode {
            routingCoordinator.reconfigureRouting()
        }
        persistence.save(currentSnapshot)
    }
}
