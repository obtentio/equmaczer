import SwiftUI

struct RecordingControls: View {
    @ObservedObject var store: EqumaczerStore
    @ObservedObject private var recording: RecordingController
    var inline: Bool = false

    init(store: EqumaczerStore, inline: Bool = false) {
        self.store = store
        self.inline = inline
        recording = store.recordingController
    }

    private var available: Bool {
        RecordingConfiguration.isAvailable(captureMode: store.routingCoordinator.currentCaptureMode ?? store.effectiveCaptureMode)
    }

    private var statusHint: String? {
        if let notice = recording.notice { return notice }
        if recording.isMacMuted { return "Mac is muted — recordings will be silent" }
        if !available { return "Requires Process Tap route" }
        if recording.configuration.enabled { return "Select \"equmaczer\" as mic in your recorder" }
        return nil
    }

    var body: some View {
        if inline {
            inlineBar
        } else {
            stackedControls
        }
    }

    /// Compact single-row strip matching `clayHeader` visual language for the main window.
    private var inlineBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(recording.configuration.enabled && available ? Color.eqG95 : Color.eqG20)
                    .frame(width: 5, height: 5)
                Toggle("Mac sound in recordings", isOn: Binding(
                    get: { recording.configuration.enabled },
                    set: { recording.updateEnabled($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(!available)
            }

            if recording.configuration.enabled {
                Rectangle()
                    .fill(Color.eqG20)
                    .frame(width: 1, height: 12)
                Toggle("Include my mic", isOn: Binding(
                    get: { recording.configuration.includeMic },
                    set: { value in Task { await recording.updateIncludeMic(value) } }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(!available || recording.requestingPermission)
            }

            Spacer(minLength: 8)

            if let hint = statusHint {
                Text(hint)
                    .foregroundStyle(Color.eqG60)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.eqT0)
        .foregroundStyle(available ? Color.eqG80 : Color.eqG60)
        .tint(Color.eqG80)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.eqG05.opacity(0.65))
        .overlay(Rectangle().strokeBorder(Color.eqG20, lineWidth: 1))
    }

    /// Vertical layout for the narrow menu-bar remote and Settings pane.
    private var stackedControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Mac sound in recordings")
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { recording.configuration.enabled },
                    set: { recording.updateEnabled($0) }))
                    .labelsHidden()
                    .controlSize(.mini)
                    .disabled(!available)
            }
            if recording.configuration.enabled {
                HStack {
                    Text("Include my mic")
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(
                        get: { recording.configuration.includeMic },
                        set: { value in Task { await recording.updateIncludeMic(value) } }))
                        .labelsHidden()
                        .controlSize(.mini)
                        .disabled(!available || recording.requestingPermission)
                }
            }
            if let hint = statusHint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.eqG60)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
