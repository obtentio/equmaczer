// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import AppKit
import Combine
import SwiftUI

// MARK: - Menu Section Helper

struct MenuSection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preset Picker

/// A picker for selecting presets, with modified indicator.
struct PresetPicker: View {
    @EnvironmentObject var store: EqumaczerStore

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                PresetMenuContentView()
            } label: {
                PresetMenuLabelView()
            }
            ModifiedIndicator()
        }
    }
}

// MARK: - Compact Preset Picker (for Menu Bar)

/// A compact preset picker suitable for the menu bar popover.
struct CompactPresetPicker: View {
    var body: some View {
        HStack(spacing: 4) {
            Menu {
                PresetMenuContentView()
            } label: {
                PresetMenuLabelView()
            }
            ModifiedIndicator()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Modified Indicator

/// A small indicator showing that the current preset has been modified.
struct ModifiedIndicator: View {
    @EnvironmentObject var store: EqumaczerStore
    
    private var viewModel: PresetViewModel {
        PresetViewModel(store: store)
    }

    var body: some View {
        if viewModel.isModified {
            Circle()
                .fill(Color.eqG80)
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - Preset Menu Helpers

struct PresetMenuLabelView: View {
    @EnvironmentObject var store: EqumaczerStore
    
    private var viewModel: PresetViewModel {
        PresetViewModel(store: store)
    }

    var body: some View {
        Text(viewModel.currentPresetName)
            .lineLimit(1)
    }
}

struct PresetMenuContentView: View {
    @EnvironmentObject var store: EqumaczerStore
    
    private var viewModel: PresetViewModel {
        PresetViewModel(store: store)
    }

    var body: some View {
        if !viewModel.hasPresets {
            Text("No presets")
                .foregroundStyle(.secondary)
        } else {
            if !store.presetManager.builtInPresets.isEmpty {
                presetSection(title: "Built-in Presets", presets: store.presetManager.builtInPresets)
            }

            if !store.presetManager.userPresets.isEmpty {
                presetSection(title: "Custom Presets", presets: store.presetManager.userPresets)
            }
        }

        Divider()
    }

    @ViewBuilder
    private func presetSection(title: String, presets: [Preset]) -> some View {
        Section(title) {
            ForEach(presets) { preset in
                presetRow(for: preset)
            }
        }
    }

    @ViewBuilder
    private func presetRow(for preset: Preset) -> some View {
        Button {
            store.loadPreset(preset)
        } label: {
            HStack {
                Text(preset.metadata.name)
                if preset.metadata.name == viewModel.selectedPresetName {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}

// MARK: - Save Preset Sheet

/// A sheet for saving a new preset or renaming an existing one.
struct SavePresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: EqumaczerStore

    @State private var presetName: String = ""
    @State private var errorMessage: String?
    @FocusState private var isNameFieldFocused: Bool

    let isRenaming: Bool
    let existingName: String?

    init(existingName: String? = nil) {
        self.existingName = existingName
        self.isRenaming = existingName != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isRenaming ? "Rename Preset" : "Save Preset")
                .font(.caption)

            TextField("Preset Name", text: $presetName)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFieldFocused)
                .onSubmit(save)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.eqG95)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(isRenaming ? "Rename" : "Save") {
                    save()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear {
            if let existing = existingName {
                presetName = existing
            } else if let selected = store.presetManager.selectedPresetName {
                presetName = selected
            }
            isNameFieldFocused = true
        }
    }

    private func save() {
        let trimmedName = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter a preset name"
            return
        }

        do {
            if isRenaming, let oldName = existingName {
                // Renaming existing preset
                try store.presetManager.renamePreset(from: oldName, to: trimmedName)
            } else {
                // Check if overwriting
                if store.presetManager.presetExists(named: trimmedName) {
                    // Overwrite existing
                    try store.saveCurrentAsPreset(named: trimmedName)
                } else {
                    // Create new
                    try store.saveCurrentAsPreset(named: trimmedName)
                }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - REW Import Sheet

/// Unified sheet for importing REW presets with support for linked or stereo mode.
/// Uses a segmented control to switch between modes.
struct REWImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: EqumaczerStore

    @State private var importMode: ImportMode = .linked
    @State private var linkedFileURL: URL?
    @State private var leftFileURL: URL?
    @State private var rightFileURL: URL?
    @State private var presetName: String = ""
    @State private var errorMessage: String?
    @State private var importWarnings: [String] = []
    @State private var showingImportWarnings = false
    @FocusState private var nameFieldFocused: Bool

    enum ImportMode: String, CaseIterable {
        case linked = "Linked"
        case stereo = "Stereo"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import REW Preset")
                .font(.headline)

            // Container with background for segmented control + descriptions
            VStack(alignment: .leading, spacing: 12) {
                // Centered segmented control
                HStack {
                    Spacer()
                    Picker("", selection: $importMode) {
                        ForEach(ImportMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Spacer()
                }
                .onChange(of: importMode) { _, _ in
                    linkedFileURL = nil
                    leftFileURL = nil
                    rightFileURL = nil
                }

                // Linked mode description
                VStack(alignment: .leading, spacing: 4) {
                    Text("Linked mode:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Same EQ settings applied to both channels")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Stereo mode description
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stereo mode:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Separate EQ settings for left and right channels")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
            )

            if importMode == .linked {
                // Linked mode: single file picker
                fileRow(
                    label: "File:",
                    fileURL: $linkedFileURL,
                    placeholder: "Select File..."
                )
            } else {
                // Stereo mode: two file pickers
                fileRow(
                    label: "Left:",
                    fileURL: $leftFileURL,
                    placeholder: "Select File..."
                )
                fileRow(
                    label: "Right:",
                    fileURL: $rightFileURL,
                    placeholder: "Select File..."
                )
            }

            // Preset name input
            HStack {
                Text("Preset Name:")
                    .frame(width: 80, alignment: .leading)
                TextField("Enter preset name", text: $presetName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFieldFocused)
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.eqG95)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Create Preset") {
                    createPreset()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(!canCreatePreset)
            }
        }
        .padding([.top, .bottom], 20)
        .padding([.leading, .trailing], 40)
        .frame(width: 450)
        .onAppear {
            nameFieldFocused = true
        }
        .alert("Import Warnings", isPresented: $showingImportWarnings) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text(importWarnings.joined(separator: "\n"))
        }
    }

    private var canCreatePreset: Bool {
        let nameValid = !presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if importMode == .linked {
            return nameValid && linkedFileURL != nil
        } else {
            return nameValid && leftFileURL != nil && rightFileURL != nil
        }
    }

    @ViewBuilder
    private func fileRow(label: String, fileURL: Binding<URL?>, placeholder: String) -> some View {
        HStack {
            Text(label)
                .frame(width: 80, alignment: .leading)
            Button(fileURL.wrappedValue?.lastPathComponent ?? placeholder) {
                selectFile { url in
                    fileURL.wrappedValue = url
                    // Auto-fill preset name from first file selected
                    if presetName.isEmpty {
                        presetName = url.deletingPathExtension().lastPathComponent
                    }
                }
            }
            .buttonStyle(.bordered)
            if fileURL.wrappedValue != nil {
                Button(action: { fileURL.wrappedValue = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func selectFile(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "txt")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a REW filter settings file"

        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }

    private func createPreset() {
        let trimmedName = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter a preset name"
            return
        }

        do {
            let settings: PresetSettings

            if importMode == .linked {
                guard let fileURL = linkedFileURL else { return }
                let result = try REWImporter.importBands(from: fileURL)

                settings = PresetSettings(
                    leftBands: result.bands,
                    rightBands: result.bands
                )

                if !result.warnings.isEmpty {
                    importWarnings = result.warnings
                }
            } else {
                guard let leftURL = leftFileURL, let rightURL = rightFileURL else { return }
                let leftResult = try REWImporter.importBands(from: leftURL)
                let rightResult = try REWImporter.importBands(from: rightURL)

                settings = PresetSettings(
                    channelMode: "stereo",
                    leftBands: leftResult.bands,
                    rightBands: rightResult.bands
                )

                importWarnings = leftResult.warnings + rightResult.warnings
            }

            let preset = Preset(
                metadata: PresetMetadata(name: trimmedName),
                settings: settings
            )

            try store.presetManager.savePreset(preset)
            store.loadPreset(preset)

            if !importWarnings.isEmpty {
                showingImportWarnings = true
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preset Toolbar

/// Presents the existing preset sheets and file panels for both menu surfaces.
struct PresetManagementHost: View {
    @EnvironmentObject private var management: PresetManagementState
    @EnvironmentObject var store: EqumaczerStore
    @State private var showingSaveSheet = false
    @State private var showingImportWarning = false
    @State private var showingEasyEffectsImportWarning = false
    @State private var showingREWImport = false
    @State private var importWarnings: [String] = []
    @State private var presetToRename: PresetRenameItem?

    struct PresetRenameItem: Identifiable {
        let id = UUID()
        let name: String
    }

    var body: some View {
        Color.clear
        .onChange(of: management.request?.id, initial: true) { _, _ in
            guard let request = management.request else { return }
            management.request = nil
            switch request.action {
            case .new: store.createNewPreset()
            case .saveAs: showingSaveSheet = true
            case .save:
                if store.presetManager.selectedPresetName != nil && store.presetManager.isModified {
                    do { try store.updateCurrentPreset() } catch { showingSaveSheet = true }
                } else { showingSaveSheet = true }
            case .rename:
                if let name = request.presetName { presetToRename = PresetRenameItem(name: name) }
            case .delete:
                if let name = request.presetName { store.deletePresetUndoable(named: name) }
            case .importNative: importNativePreset()
            case .importREW: importREWPreset()
            case .importEasyEffects: showingEasyEffectsImportWarning = true
            case .exportNative, .exportEasyEffects, .exportREW:
                guard let name = request.presetName, let preset = store.presetManager.preset(named: name) else { return }
                switch request.action {
                case .exportNative: exportNativePreset(preset)
                case .exportEasyEffects: exportEasyEffectsPreset(preset)
                default: exportREWPreset(preset)
                }
            }
        }
        .sheet(isPresented: $showingSaveSheet) {
            SavePresetSheet()
        }
        .sheet(item: $presetToRename) { item in
            SavePresetSheet(existingName: item.name)
        }
        .alert("Import Warnings", isPresented: $showingImportWarning) {
            Button("OK") {}
        } message: {
            Text(importWarnings.joined(separator: "\n"))
        }
        .sheet(isPresented: $showingEasyEffectsImportWarning) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Limited Functionality")
                    .font(.headline)
                
                Text("""
                Importing from EasyEffects has limitations:
                
                • Only the equalizer bands are imported
                • Filter mode (RLC BT/MT, etc.) and slope (x1, x2, x4) are not supported
                • Per-channel (split) EQ is not supported - mono EQ is used
                • Non-EQ plugins (compressor, limiter, reverb) are not imported
                • Input/output gain and some band settings may differ slightly
                
                The imported preset will only contain the equalizer bands.
                """)
                
                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingEasyEffectsImportWarning = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Continue") {
                        showingEasyEffectsImportWarning = false
                        importEasyEffectsPreset()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 500)
        }
        .sheet(isPresented: $showingREWImport) {
            REWImportSheet()
        }
    }

    // MARK: - Import/Export

    private func importNativePreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: Preset.fileExtension)!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a preset file to import"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let preset = try store.presetManager.importPreset(from: url)
                store.loadPreset(preset)
            } catch {
                // Show error alert
                let alert = NSAlert()
                alert.messageText = "Import Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private func exportNativePreset(_ preset: Preset) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: Preset.fileExtension)!]
        panel.nameFieldStringValue = preset.filename
        panel.message = "Export preset"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try store.presetManager.exportPreset(preset, to: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private func importEasyEffectsPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an EasyEffects preset file"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let result = try EasyEffectsImporter.importPreset(from: url)
                try store.presetManager.savePreset(result.preset)
                store.loadPreset(result.preset)

                if !result.warnings.isEmpty {
                    importWarnings = result.warnings
                    showingImportWarning = true
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Import Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private func exportREWPreset(_ preset: Preset) {
        let stereo = preset.settings.channelMode == "stereo"
        let channels = stereo ? [preset.settings.leftBands, preset.settings.rightBands] : [preset.settings.leftBands]
        for (index, bands) in channels.enumerated() {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            let suffix = stereo ? (index == 0 ? "-left" : "-right") : ""
            panel.nameFieldStringValue = preset.metadata.name + suffix + ".txt"
            panel.message = "Export REW filters\(stereo ? (index == 0 ? " — left ear" : " — right ear") : ""). Global gains stay in the native preset."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try REWExporter.export(bands: Array(bands.prefix(preset.settings.activeBandCount)))
                    .write(to: url, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
                return
            }
        }
    }

    private func importREWPreset() {
        showingREWImport = true
    }

    private func exportEasyEffectsPreset(_ preset: Preset) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = EasyEffectsExporter.filename(for: preset)
        panel.message = "Export to EasyEffects format"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try EasyEffectsExporter.export(preset, to: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}

