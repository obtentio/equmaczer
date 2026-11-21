import SwiftUI

/// The preset shelf shares one row with saving and the plain-language editor.
struct PresetRowView: View {
    @EnvironmentObject private var store: EqumaczerStore
    let onSave: () -> Void
    @State private var showManagement = false
    @State private var showSnapshots = false
    @State private var showOverflow = false

    var body: some View {
        GeometryReader { geometry in
            let presets = store.presetManager.presets.sorted { $0.metadata.name.localizedStandardCompare($1.metadata.name) == .orderedAscending }
            let widths = presets.map { ($0.metadata.name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width + 14 }
            let fit = PresetRowLayout.fit(chipWidths: widths, width: geometry.size.width)
            HStack(spacing: 5) {
                ForEach(Array(presets.prefix(fit.visibleCount))) { preset in
                    Button(preset.metadata.name) { store.loadPreset(preset) }
                        .foregroundStyle(store.presetManager.selectedPresetName == preset.metadata.name ? Color.eqG95 : Color.eqG60)
                        .contextMenu { PresetManagementMenu(presetName: preset.metadata.name) }
                        .draggable(preset.metadata.name)
                        .help("Apply \(preset.metadata.name), or drag to Clay to blend")
                }
                if fit.visibleCount < presets.count {
                    Button("+ \(presets.count - fit.visibleCount)") { showOverflow.toggle() }
                    .fixedSize()
                    .popover(isPresented: $showOverflow) {
                        VStack(alignment: .leading, spacing: 10) {
                            PagedList(items: Array(presets.dropFirst(fit.visibleCount)), id: \.id, pageSize: 8) { preset in
                                Button(preset.metadata.name) { store.loadPreset(preset); showOverflow = false }
                                    .buttonStyle(.plain).draggable(preset.metadata.name)
                                    .contextMenu { PresetManagementMenu(presetName: preset.metadata.name) }
                            }
                            Divider()
                            Button("Manage presets…") { showOverflow = false; showManagement = true }
                            Button("Saved snapshots…") { showOverflow = false; showSnapshots = true }
                        }.font(.eqT1).padding(12).frame(width: 280)
                    }
                }
                Button("+ Save current", action: onSave).fixedSize()
                    .contextMenu {
                        Button("Manage presets…") { showManagement = true }
                        Button("Saved snapshots…") { showSnapshots = true }
                    }
                DescribeFieldView().frame(minWidth: 110, maxWidth: fit.describeWidth)
            }
            .font(.eqT0).controlSize(.small).buttonStyle(WindowChipStyle())
        }
        .frame(height: 28)
        .background { PresetManagementHost().frame(width: 0, height: 0).clipped().accessibilityHidden(true) }
        .sheet(isPresented: $showManagement) { VStack { Menu("Manage presets…") { PresetManagementMenu(presetName: store.presetManager.selectedPresetName) }; Button("Done") { showManagement = false } }.padding(16).frame(width: 600) }
        .sheet(isPresented: $showSnapshots) { VStack { SavedSnapshotsView(); Button("Done") { showSnapshots = false } }.padding(16).frame(width: 500, height: 320) }
    }
}

/// Reserve the action and overflow first; the field shrinks before chips leave.
enum PresetRowLayout {
    static func fit(chipWidths: [CGFloat], width: CGFloat) -> (visibleCount: Int, describeWidth: CGFloat) {
        let saveWidth: CGFloat = 110
        let overflowWidth: CGFloat = 45
        var available = max(0, width - saveWidth - 5)
        var count = chipWidths.count
        var used = chipWidths.reduce(0) { $0 + $1 + 5 }
        if used + 110 > available { available = max(0, available - overflowWidth - 5) }
        while count > 0 && used + 110 > available {
            count -= 1
            used -= chipWidths[count] + 5
        }
        return (count, min(220, max(110, available - used)))
    }
}
