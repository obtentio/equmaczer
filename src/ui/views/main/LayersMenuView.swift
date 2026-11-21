import SwiftUI

struct LayersMenuView: View {
    @ObservedObject var store: EqumaczerStore
    @ObservedObject private var correction: CorrectionController
    @ObservedObject private var hearing: HearingController
    @ObservedObject private var channel: ChannelController
    @State private var showLayers = false
    @State private var showCorrection = false

    init(store: EqumaczerStore) {
        self.store = store
        correction = store.correctionController
        hearing = store.hearingController
        channel = store.channelController
    }
    var body: some View {
        Button("Layers ▾") { showLayers.toggle() }
            .popover(isPresented: $showLayers) {
                VStack(alignment: .leading, spacing: 12) {
                    layer("My EQ", source: store.presetManager.selectedPresetName ?? "Manual curve", isOn: Binding(
                        get: { store.eqConfiguration.userEQEnabled },
                        set: { store.eqConfiguration.userEQEnabled = $0; store.routingCoordinator.reapplyConfiguration() }))
                    HStack {
                        layer("Correction", source: correction.activeProfile?.sourceName ?? correction.currentDeviceName ?? "No device", isOn: $correction.enabled)
                        Button("Open…") { showLayers = false; showCorrection = true }
                    }
                    layer("Hearing", source: hearing.state.sourceLabel + " · estimate, not medical", isOn: Binding(get: { hearing.state.enabled }, set: { hearing.setEnabled($0) }))
                    layer("Channel", source: channelSource, isOn: $channel.enabled)
                    layer("Loudness", source: "\(Int(store.loudnessStrength * 100))% · follows volume", isOn: Binding(get: { store.loudnessEnabled }, set: { store.loudnessEnabled = $0 }))
                    Slider(value: Binding(get: { store.loudnessStrength }, set: { store.loudnessStrength = $0 }), in: 0...1)
                        .accessibilityLabel("Loudness strength")
                }.font(.eqT1).padding(14).frame(width: 390).tint(Color.eqG80)
            }
            .sheet(isPresented: $showCorrection) {
                VStack {
                    DeviceCorrectionView(store: store, controller: correction)
                    Button("Done") { showCorrection = false }
                }.padding(12)
            }
    }
    private var channelSource: String {
        guard let active = channel.activeChannel else { return "Automatic · no channel" }
        return "\(active.displayName) · \(channel.state.treatmentName(for: active))" + (channel.state.dialogue.contains(active) ? " · dialogue clarity" : "")
    }
    private func layer(_ name: String, source: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Toggle(name, isOn: isOn).toggleStyle(.switch).controlSize(.small).fixedSize()
            Spacer()
            Text(source).foregroundStyle(Color.eqG60).lineLimit(2)
        }
    }
}
