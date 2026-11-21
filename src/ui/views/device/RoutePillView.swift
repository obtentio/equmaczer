import SwiftUI

/// The output is the compact readout; the full route and controls live behind it.
struct RoutePillView: View {
    @EnvironmentObject private var store: EqumaczerStore
    let viewModel: RoutingViewModel
    @State private var showDevicePicker = false

    var body: some View {
        Button { showDevicePicker.toggle() } label: {
            HStack(spacing: 6) {
                Circle().fill(blocked ? Color.eqSignal : Color.eqG60).frame(width: 6, height: 6)
                Text(viewModel.outputDeviceName).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9))
            }.font(.eqT0)
        }
        .help("\(viewModel.detailedStatusText) · \(viewModel.inputDeviceName) → EQ → \(viewModel.outputDeviceName)")
        .popover(isPresented: $showDevicePicker) {
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.detailedStatusText).font(.eqT1).foregroundStyle(blocked ? Color.eqSignal : Color.eqG60)
                OutputDevicePickerView(layout: .vertical).disabled(!viewModel.manualModeEnabled)
                InputDevicePickerView(layout: .vertical).disabled(!viewModel.manualModeEnabled)
                Toggle("Follow macOS sound settings", isOn: Binding(
                    get: { !viewModel.manualModeEnabled },
                    set: { if $0 { store.switchToAutomaticMode() } else { store.switchToManualMode() } }))
                    .toggleStyle(.switch).controlSize(.small)
                Text("When on, equmaczer switches output when you switch it in macOS. Turn it off to pick the input and output yourself.")
                    .font(.eqT0).foregroundStyle(Color.eqG60)
                if viewModel.manualModeEnabled {
                    Toggle("Audio Routing", isOn: Binding(get: { viewModel.isActive }, set: { _ in viewModel.toggleRouting() }))
                        .disabled(!viewModel.canToggleRouting).toggleStyle(.switch).controlSize(.small)
                }
            }.padding(14).frame(width: 340).tint(Color.eqG80)
        }
    }
    private var blocked: Bool {
        if case .driverNotInstalled = viewModel.status { return true }
        return viewModel.isErrorState
    }
}
