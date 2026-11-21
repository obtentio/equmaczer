import SwiftUI

/// Both menu surfaces target the named chip, or the current preset in File.
struct PresetManagementRequest: Identifiable {
    let id = UUID()
    enum Action { case new, save, saveAs, rename, delete, importNative, importREW, importEasyEffects, exportNative, exportREW, exportEasyEffects }
    let action: Action
    let presetName: String?
}

/// Retains File-menu actions until the main window's presentation host is mounted.
@MainActor
final class PresetManagementState: ObservableObject {
    @Published var request: PresetManagementRequest?
}

struct PresetManagementMenu: View {
    @EnvironmentObject private var management: PresetManagementState
    @Environment(\.openWindow) private var openWindow
    let presetName: String?

    var body: some View {
        Button("New preset") { send(.new) }
        Button("Save current preset") { send(.save) }
        Button("Save current EQ as…") { send(.saveAs) }
        Divider()
        Button("Rename preset…") { send(.rename) }.disabled(presetName == nil)
        Button("Delete preset", role: .destructive) { send(.delete) }.disabled(presetName == nil)
        Divider()
        Menu("Import preset") {
            Button("equmaczer…") { send(.importNative) }
            Button("REW…") { send(.importREW) }
            Button("EasyEffects…") { send(.importEasyEffects) }
        }
        Menu("Export preset") {
            Button("equmaczer…") { send(.exportNative) }
            Button("REW…") { send(.exportREW) }
            Button("EasyEffects…") { send(.exportEasyEffects) }
        }.disabled(presetName == nil)
    }

    private func send(_ action: PresetManagementRequest.Action) {
        openWindow(id: "equaliser")
        management.request = PresetManagementRequest(action: action, presetName: presetName)
    }
}
