// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// C4: the Cmd+K palette — one field for the whole sound.
/// The catalogue is built from live state at open time; the
/// matching (including composite device + channel + preset
/// actions) lives in PaletteIndex.
struct CommandPaletteView: View {
    let index: PaletteIndex
    let onClose: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let results = index.results(for: query)
        VStack(alignment: .leading, spacing: 0) {
            TextField("Find a setting, preset, device or channel", text: $query)
                .textFieldStyle(.plain)
                .font(.eqT3)
                .foregroundStyle(Color.eqG95)
                .padding(12)
                .focused($fieldFocused)

            Rectangle()
                .fill(Color.eqG20)
                .frame(height: 1)

            if results.isEmpty {
                Text("Nothing matches.")
                    .font(.eqT1)
                    .foregroundStyle(Color.eqG60)
                    .padding(12)
            } else {
                ForEach(Array(results.enumerated()), id: \.element.id) { i, action in
                    Button {
                        action.execute()
                        onClose()
                    } label: {
                        HStack(spacing: 8) {
                            Text(action.title)
                                .font(.eqT1)
                                .foregroundStyle(Color.eqG95)
                            Spacer()
                            if let detail = action.detail {
                                Text(detail)
                                    .font(.eqT0)
                                    .foregroundStyle(Color.eqG60)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(i == selection ? Color.eqG20 : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 440)
        .background(Color.eqG10)
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _, _ in selection = 0 }
        .onKeyPress(.downArrow) {
            selection = min(selection + 1, max(0, results.count - 1))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selection = max(selection - 1, 0)
            return .handled
        }
        .onKeyPress(.return) {
            if results.indices.contains(selection) {
                results[selection].execute()
                onClose()
            }
            return .handled
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }

    /// The live catalogue: commands, channels, devices, presets.
    @MainActor
    static func catalogue(store: EqumaczerStore) -> PaletteIndex {
        var actions: [PaletteAction] = []



        actions.append(PaletteAction(
            id: "compare-flat", title: "Compare — Flat",
            detail: store.compareMode == .flat ? "active" : nil,
            keywords: ["compare", "flat", "ab"],
            execute: { store.compareMode = .flat }
        ))
        actions.append(PaletteAction(
            id: "compare-eq", title: "Compare — EQ",
            detail: store.compareMode == .eq ? "active" : nil,
            keywords: ["compare", "eq", "ab"],
            execute: { store.compareMode = .eq }
        ))
        actions.append(PaletteAction(
            id: "bypass", title: store.isBypassed ? "Bypass — Off" : "Bypass — On",
            keywords: ["bypass", "off", "on"],
            execute: { store.isBypassed.toggle() }
        ))
        for mode in [CaptureMode.processTap, .sharedMemory, .halInput] {
            actions.append(PaletteAction(
                id: "capture-\(mode.rawValue)", title: "Capture — \(mode.displayName)",
                detail: store.captureMode == mode ? "active" : nil,
                keywords: ["capture", "route", "driver"],
                execute: { store.captureMode = mode }
            ))
        }
        actions.append(PaletteAction(
            id: "flatten", title: "Flatten bands",
            detail: "undoable",
            keywords: ["flatten", "reset", "gains", "zero"],
            execute: { store.flattenBands() }
        ))
        actions.append(PaletteAction(
            id: "new-preset", title: "New preset — reset bands",
            detail: "undoable",
            keywords: ["new", "reset", "blank"],
            execute: { store.createNewPreset() }
        ))

        for channel in AudioChannel.allCases {
            actions.append(PaletteAction(
                id: "channel-\(channel.rawValue)",
                title: "Channel — \(channel.displayName)",
                facet: .channel(channel.displayName),
                keywords: ["channel", "pin"],
                execute: { store.channelController.setPinned(channel) }
            ))
        }
        actions.append(PaletteAction(
            id: "channel-auto", title: "Channel — Auto",
            keywords: ["channel", "auto", "unpin"],
            execute: { store.channelController.setPinned(nil) }
        ))

        for device in store.outputDevices where device.isRealDevice {
            actions.append(PaletteAction(
                id: "device-\(device.uid)",
                title: "Output — \(device.name)",
                facet: .device(device.name),
                keywords: ["output", "device"],
                execute: { store.selectedOutputDeviceID = device.uid }
            ))
        }

        for preset in store.presetManager.builtInPresets + store.presetManager.userPresets {
            actions.append(PaletteAction(
                id: "preset-\(preset.metadata.name)",
                title: "Preset — \(preset.metadata.name)",
                facet: .preset(preset.metadata.name),
                keywords: ["preset"],
                execute: { store.loadPreset(preset) }
            ))
        }

        return PaletteIndex(actions: actions)
    }
}
