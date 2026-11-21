import SwiftUI

struct RecordingControls: View {
    @ObservedObject var store: EqumaczerStore
    @ObservedObject private var recording: RecordingController

    init(store: EqumaczerStore) {
        self.store = store
        recording = store.recordingController
    }

    private var available: Bool {
        RecordingConfiguration.isAvailable(captureMode: store.routingCoordinator.currentCaptureMode ?? store.effectiveCaptureMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle("Mac sound in recordings", isOn: Binding(
                get: { recording.configuration.enabled }, set: { recording.updateEnabled($0) }))
                .disabled(!available)
            if recording.isMacMuted {
                Text("Your Mac is muted, so recordings are silent too.")
            }
            if !available {
                Text("Works on the Process Tap route.")
            }
            if recording.configuration.enabled {
                Text("In the recorder, choose equmaczer as the microphone.")
                Toggle("Include my mic", isOn: Binding(
                    get: { recording.configuration.includeMic },
                    set: { value in Task { await recording.updateIncludeMic(value) } }))
                    .disabled(!available || recording.requestingPermission)
            }
            if let notice = recording.notice { Text(notice) }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.eqG80)
        .tint(Color.eqG80)
        .toggleStyle(.switch)
    }
}

struct RecordingMicrophonePicker: View {
    @ObservedObject var store: EqumaczerStore
    @ObservedObject private var recording: RecordingController

    init(store: EqumaczerStore) {
        self.store = store
        recording = store.recordingController
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RecordingControls(store: store)
            Picker("Microphone", selection: Binding(
                get: { recording.configuration.microphoneUID ?? "" },
                set: { recording.updateMicrophone($0.isEmpty ? nil : $0) })) {
                Text("System default input").tag("")
                ForEach(store.inputDevices.filter { !$0.isDriver }) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .disabled(!recording.configuration.includeMic)
        }
        .onReceive(recording.$configuration) { configuration in
            if configuration.includeMic { store.enumerateInputDevices() }
        }
    }
}
