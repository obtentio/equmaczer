// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// Output device correction panel: loudness compensation, the current
/// device's correction profile, and its preference trims.
///
/// Everything here writes to the correction layer (owned by
/// `CorrectionController`) — never to the user EQ — so a correction
/// follows its device and coexists with any preset.
struct DeviceCorrectionView: View {
    @ObservedObject var store: EqumaczerStore
    @ObservedObject var controller: CorrectionController

    var importURL: URL? = nil

    @State private var message: String?
    @State private var messageIsError = false
    @State private var opraCatalog: OpraCatalog?
    @State private var showOpraPicker = false
    @State private var showBlindTest = false
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("Output Device Correction")
                .font(.subheadline)
                .fontWeight(.semibold)

            Toggle("Loudness", isOn: Binding(
                get: { store.loudnessEnabled },
                set: { store.loudnessEnabled = $0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("At low volume your hearing loses bass and some treble. Loudness compensation restores the balance of a full-volume listen, following the ISO 226 equal-loudness contours and tracking the output device's volume. Strength is the calibration: systems differ, so set it by ear.")

            if store.loudnessEnabled {
                HStack(spacing: 8) {
                    Text("Strength")
                        .font(.caption)
                    Slider(value: Binding(
                        get: { store.loudnessStrength },
                        set: { store.loudnessStrength = $0 }
                    ), in: 0...1)
                    Text("\(Int(store.loudnessStrength * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }

            if let deviceName = controller.currentDeviceName {
                Text(deviceName)
                    .font(.caption)
                    .fontWeight(.medium)
            }

            if let profile = controller.activeProfile, controller.previewProfile == nil {
                Text("\(profile.sourceName) · \(profile.bands.count) bands · preamp \(profile.preampDB, specifier: "%.1f") dB")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                provenanceLine(for: profile)

                trimSliders(bass: profile.bassTrimDB, treble: profile.trebleTrimDB)

                blendSlider(percent: profile.blendPercent ?? 100)
                    .disabled(controller.previewProfile != nil)

                Button("Clear correction for this device") {
                    controller.clearCorrection()
                }
                .font(.caption)
                .disabled(controller.previewProfile != nil)
            } else if controller.previewProfile == nil {
                Text("No correction for this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                Button("Import AutoEq…") { importAutoEq() }
                Button("Import OPRA…") { importOpra() }
                Button("Use current EQ") { useCurrentEQ() }
                if currentDeviceIsBuiltIn {
                    Button("Speaker guard…") { stageSpeakerGuard() }
                        .help("Stage the generic guard for small built-in speakers: cuts the deep lows they cannot reproduce and tames the boom region. A generic shape, not a measurement of this model")
                }
            }
            .font(.caption)
            .disabled(controller.currentDeviceUID == nil || controller.previewProfile != nil || importing)

            if let preview = controller.previewProfile {
                Divider()

                Text("Previewing — \(preview.sourceName) · \(preview.bands.count) bands · preamp \(preview.preampDB, specifier: "%.1f") dB")
                    .font(.caption)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)

                provenanceLine(for: preview)

                Text("Level-matched for comparison.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                trimSliders(bass: preview.bassTrimDB, treble: preview.trebleTrimDB)

                blendSlider(percent: preview.blendPercent ?? 100)

                Text("Blend — 100% is the full measured correction. A new correction starts at 70%.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Hear preview") { controller.setPreviewAudible(true) }
                        .disabled(controller.previewAudible)
                    Button("Hear current") { controller.setPreviewAudible(false) }
                        .disabled(!controller.previewAudible)
                }
                .font(.caption)

                HStack(spacing: 8) {
                    Button("Import") { commitPreview() }
                    Button("Cancel") { cancelPreview() }
                    Button("Hear blind") { showBlindTest = true }
                        .help("Hear the preview and your current sound as A and B, labels hidden, and pick before you know which was which — the pick imports or cancels")
                }
                .font(.caption)
                .sheet(isPresented: $showBlindTest) {
                    BlindABView(store: store, correctionController: controller, mode: .correction)
                }
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(messageIsError ? Color.eqG95 : Color.eqG80)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minWidth: 0, idealWidth: 376, maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if let importURL { importProfile(url: importURL) }
        }
        .sheet(isPresented: $showOpraPicker) {
            if let catalog = opraCatalog {
                OpraPickerView(catalog: catalog) { product, preset in
                    beginOpraPreview(product: product, preset: preset)
                }
            }
        }
    }

    /// The profile's provenance (A7), when the source names an
    /// author: the author first (OPRA's attribution rule), then the
    /// source's own details — where the rig and target live.
    @ViewBuilder
    private func provenanceLine(for profile: DeviceCorrectionProfile) -> some View {
        if let author = profile.author {
            Text(profile.sourceDetails.map { "\(author) · \($0)" } ?? author)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The two preference knobs (A2): broad shelves over the
    /// correction, as sliders with a dB readout. One helper serves
    /// the saved profile and the preview; the controller routes the
    /// setters to whichever state is live.
    /// The correction blend (C3): one slider serving the saved
    /// profile and the preview, routed by the controller like
    /// the trims.
    private func blendSlider(percent: Double) -> some View {
        HStack(spacing: 8) {
            Text("Blend")
                .font(.caption)
                .frame(width: 44, alignment: .leading)
            Slider(
                value: Binding(get: { percent }, set: { controller.setBlendPercent($0) }),
                in: 0...100,
                step: 1
            )
            Text("\(Int(percent.rounded()))%")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func trimSliders(bass: Float, treble: Float) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            trimSlider(label: "Bass", value: bass, range: -10...12) {
                controller.setBassTrim($0)
            }
            trimSlider(label: "Treble", value: treble, range: -10...10) {
                controller.setTrebleTrim($0)
            }
        }
    }

    private func trimSlider(label: String, value: Float, range: ClosedRange<Float>, onChange: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 44, alignment: .leading)
            Slider(
                value: Binding(get: { value }, set: { onChange($0) }),
                in: range,
                step: 0.5
            )
            Text(String(format: "%+.1f dB", value))
                .font(.caption)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func importAutoEq() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "txt")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an AutoEq parametric equaliser file"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        importAutoEq(url: url)
    }

    private func importAutoEq(url: URL) {
        do {
            let warnings = try controller.beginAutoEqPreview(url: url)
            message = warnings.isEmpty
                ? "Previewing — nothing is saved yet."
                : warnings.joined(separator: " ")
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func importOpra() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "jsonl")!, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an OPRA database file (database_v1.jsonl)"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        importOpra(url: url)
    }

    private func importProfile(url: URL) {
        switch CorrectionProfileFile.type(for: url) {
        case .autoEq: importAutoEq(url: url)
        case .opra: importOpra(url: url)
        case nil: break
        }
    }

    private func importOpra(url: URL) {
        guard !importing else { return }
        importing = true
        message = "Reading OPRA catalogue…"
        Task {
            defer { importing = false }
            do {
                let catalog = try await Task.detached(priority: .userInitiated) {
                    try OpraImporter.parseCatalog(from: url)
                }.value
                guard !catalog.products.isEmpty else {
                    message = "No usable presets found in that file."
                    messageIsError = true
                    return
                }
                opraCatalog = catalog
                message = nil
                showOpraPicker = true
            } catch {
                message = error.localizedDescription
                messageIsError = true
            }
        }
    }

    /// D6: the guard stages only for the built-in output — it
    /// is a shape for small built-in speakers, and offering it
    /// for a headphone or an interface would be a category error.
    private var currentDeviceIsBuiltIn: Bool {
        guard let uid = controller.currentDeviceUID,
              let device = store.deviceManager.device(forUID: uid)
        else { return false }
        return device.isBuiltIn
    }

    private func stageSpeakerGuard() {
        guard let uid = controller.currentDeviceUID else { return }
        let result = SpeakerGuard.importResult(
            deviceUID: uid,
            deviceName: controller.currentDeviceName ?? "Built-in Output"
        )
        _ = controller.beginPreview(result, initialBlendPercent: 100)
        message = "Previewing the speaker guard — nothing is saved yet."
        messageIsError = false
    }

    private func beginOpraPreview(product: OpraProduct, preset: OpraPreset) {
        guard let uid = controller.currentDeviceUID else { return }
        let result = OpraImporter.makeProfile(
            product: product,
            preset: preset,
            deviceUID: uid,
            deviceName: controller.currentDeviceName ?? "Output Device"
        )
        let warnings = controller.beginPreview(result)
        message = warnings.isEmpty
            ? "Previewing — nothing is saved yet."
            : warnings.joined(separator: " ")
        messageIsError = false
    }

    private func commitPreview() {
        controller.commitPreview()
        message = "Correction imported for this device."
        messageIsError = false
    }

    private func cancelPreview() {
        controller.cancelPreview()
        message = "Preview discarded — nothing was saved."
        messageIsError = false
    }

    private func useCurrentEQ() {
        do {
            try controller.useCurrentEQAsCorrection()
            message = "Current EQ saved as this device's correction."
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }
}
