// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI
import Combine

/// One screen: Clay, presets and bands, with Measure alongside or below.
struct EQWindowView: View {
    @EnvironmentObject var store: EqumaczerStore
    @EnvironmentObject var windowActivation: WindowActivationController
    @StateObject private var driverManager = DriverManager.shared
    @EnvironmentObject private var sceneEngine: SceneEngine
    @State private var showDriverSheet = true
    @State private var showDriverUpdateSheet = false
    @State private var showSaveSheet = false
    @Binding var showPalette: Bool
    @State private var blendPreset: Preset? = nil
    @State private var blend: Double = 0.5
    @State private var panicActive = false
    @State private var priorPanicBypass: Bool?
    @State private var priorCompare: CompareMode?
    @State private var blendBaseline: SoundState?
    @State private var correctionDrop: CorrectionFileDrop?
    @State private var dropNotice: String?
    @State private var receipt: String? = nil
    @AppStorage("keys.panic") private var panicKey = "P"
    @AppStorage("keys.compare") private var compareKey = "C"
    @AppStorage("keys.compareHold") private var compareHold = true
    @State private var sketchArmed = false
    @State private var checkController: TranslationCheckController?

    /// Whether the driver installation overlay should be shown.
    private var needsDriverInstallation: Bool {
        !driverManager.isReady
            && !store.routingCoordinator.manualModeEnabled
            && !store.routingCoordinator.usesDriverlessProcessTap
    }

    /// Whether the driver needs updating (outdated version).
    private var needsDriverUpdate: Bool {
        store.showDriverUpdateRequired && !store.routingCoordinator.manualModeEnabled
    }

    /// View model for routing status.
    private var routingViewModel: RoutingViewModel {
        RoutingViewModel(store: store)
    }

    var body: some View {
        ZStack {
        GeometryReader { geometry in
            let narrow = geometry.size.width < 900
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    VStack(spacing: 8) {
                        clayHeader
                        RecordingControls(store: store, inline: true)
                        ClayStageView(sketchArmed: $sketchArmed)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .dropDestination(for: String.self) { names, _ in
                                guard let name = names.first,
                                      let preset = store.presetManager.preset(named: name) else { return false }
                                blendBaseline = store.captureSoundState()
                                blendPreset = preset
                                blend = 0.5
                                store.previewBlend(preset: preset, amount: blend, from: blendBaseline!)
                                return true
                            }
                        PresetRowView(onSave: { showSaveSheet = true })
                        BandSlidersView()
                            .frame(height: min(220, max(120, (geometry.size.height + 38) * 0.24)))
                        if let sceneReceipt = sceneEngine.receipt {
                            HStack {
                                Text(sceneReceipt.text)
                                if sceneReceipt.canUndo { Button("Undo") { sceneEngine.undo() } }
                            }.font(.eqT0)
                        } else if let receipt { Text(receipt).font(.eqT0) }
                    }
                    .padding(10)
                    .background(Color.eqG10)
                    if !narrow {
                        MeasureView(store: store, checkController: checkController, compact: false)
                            .frame(width: geometry.size.width >= 1300 ? 230 : 200)
                    }
                }
                if let dropNotice {
                    Text(dropNotice).font(.eqT0).foregroundStyle(Color.eqG60)
                }
                if narrow { MeasureView(store: store, checkController: checkController, compact: true) }
            }.padding(6)
        }
        if store.compareMode == .flat {
            CompareVeil(compareKey: compareKey, hold: compareHold)
        }
        if panicActive {
            PanicVeil()
        }
        if let preset = blendPreset {
            ZStack {
                Color.eqG00.opacity(0.45)
                BlendDial(
                    presetName: preset.metadata.name,
                    blend: $blend,
                    onApply: { applyCurrentBlend(preset) },
                    onCancel: { cancelBlend() }
                )
            }
        }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.count == 1, let url = urls.first,
                  CorrectionProfileFile.type(for: url) != nil else {
                dropNotice = "Not a correction profile"
                return true
            }
            dropNotice = nil
            correctionDrop = CorrectionFileDrop(url: url)
            return true
        }
        .sheet(item: $correctionDrop) { file in
            VStack {
                DeviceCorrectionView(store: store, controller: store.correctionController, importURL: file.url)
                Button("Done") { correctionDrop = nil }
            }.padding(12)
        }
        .background(Color.eqG05)
        .preferredColorScheme(.dark)
        .tint(Color.eqG80)
        .sheet(isPresented: $showPalette) {
            CommandPaletteView(index: CommandPaletteView.catalogue(store: store)) { showPalette = false }
        }
        .frame(minWidth: 832, minHeight: 520)
        .onChange(of: blend) { _, amount in
            if let preset = blendPreset, let baseline = blendBaseline {
                store.previewBlend(preset: preset, amount: amount, from: baseline)
            }
        }
        .onDisappear { cancelBlend() }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 7) {
                    DotArcMark(cell: 15.0 / 7.0)
                    Text("equmaczer").font(.eqT2Medium)
                }
            }
            ToolbarItem(placement: .principal) {
                CallRescueNotice(controller: store.callCliffController)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                RoutePillView(viewModel: routingViewModel)
                AppsMenuView(store: store)
                LayersMenuView(store: store)
                HStack(spacing: 6) {
                    Text("System EQ").font(.eqT0)
                    SystemEQToggleView().labelsHidden()
                }
            }
        }
        .background(
            WindowAccessor { window in
                store.setEqumaczerWindow(window)
            }
        )
        .background(
            AppKeyMonitor(
                isEnabled: blendPreset == nil && !showPalette && !showSaveSheet,
                panicKey: panicKey,
                compareKey: compareKey,
                compareHold: compareHold,
                onPanic: { held in
                    if held {
                        if priorPanicBypass == nil { priorPanicBypass = store.isBypassed }
                        store.isBypassed = true
                    } else if let prior = priorPanicBypass {
                        if store.isBypassed { store.isBypassed = prior }
                        priorPanicBypass = nil
                    }
                    panicActive = held
                },
                onCompare: { held in
                    if !compareHold {
                        store.compareMode = store.compareMode == .flat ? .eq : .flat
                    } else if held {
                        if priorCompare == nil { priorCompare = store.compareMode }
                        store.compareMode = .flat
                    } else if let prior = priorCompare {
                        if store.compareMode == .flat { store.compareMode = prior }
                        priorCompare = nil
                    }
                }
            )
        )
        .onAppear {
            windowActivation.windowBecameVisible(.equaliser)
            store.meterStore.windowBecameVisible()
            sceneEngine.start(store: store)
            if checkController == nil { checkController = TranslationCheckController(store: store) }
        }
        .onDisappear {
            windowActivation.windowBecameHidden(.equaliser)
            store.meterStore.windowBecameHidden()
        }
        .sheet(isPresented: $showDriverSheet) {
            DriverInstallationView(
                onInstall: {
                    store.handleDriverInstalled()
                },
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
            .environmentObject(store)
            .frame(minWidth: 500, minHeight: 400)
        }
        .onChange(of: needsDriverInstallation) { _, newValue in
            showDriverSheet = newValue
        }
        .sheet(isPresented: $showDriverUpdateSheet) {
            DriverInstallationView(
                onInstall: {
                    store.handleDriverInstalled()
                },
                onQuit: {
                    showDriverUpdateSheet = false
                }
            )
            .environmentObject(store)
            .frame(minWidth: 500, minHeight: 400)
        }
        .onChange(of: needsDriverUpdate) { _, newValue in
            // The unified driver sheet handles updates in place; Settings
            // is no longer hijacked for them.
            showDriverUpdateSheet = newValue
        }
        .onAppear {
            showDriverSheet = needsDriverInstallation
            showDriverUpdateSheet = needsDriverUpdate
        }
        .onReceive(NotificationCenter.default.publisher(for: .savePresetShortcut)) { _ in
            showSaveSheet = true
        }
        .sheet(isPresented: $showSaveSheet) {
            SavePresetSheet()
                .environmentObject(store)
        }
    }

    private var clayHeader: some View {
        HStack(spacing: 8) {
            Text(store.presetManager.selectedPresetName ?? "Untitled curve").font(.eqT2Medium).lineLimit(1)
            if store.presetManager.isModified { Text("edited").foregroundStyle(Color.eqG60) }
            Spacer(minLength: 0)
            Text(String(format: "ceiling %.1f dB", store.eqConfiguration.autoPreampDB + store.eqConfiguration.correctionPreampDB))
                .help(headroomHelp)
            Button("Spectrum") { store.spectrumEnabled.toggle() }
                .foregroundStyle(store.spectrumEnabled ? Color.eqG95 : Color.eqG60)
            Button("Sketch") { sketchArmed.toggle() }
                .foregroundStyle(sketchArmed ? Color.eqG95 : Color.eqG60)
            BandCountControl(menuOnly: true)
            Menu((store.channelMode == .linked ? "Linked" : (store.channelFocus == .left ? "Left" : "Right")) + " ▾") {
                Button("Linked") { store.channelMode = .linked }
                Button("Left") { store.channelMode = .stereo; store.channelFocus = .left }
                Button("Right") { store.channelMode = .stereo; store.channelFocus = .right }
            }.fixedSize()
        }
        .font(.eqT0).buttonStyle(WindowChipStyle()).controlSize(.small)
    }

    private var headroomHelp: String {
        let config = store.eqConfiguration
        let breakdown = String(format: "Auto headroom: CUT %.1f · CORR %.1f · TOTAL %.1f dB", config.autoPreampDB, config.correctionPreampDB, config.autoPreampDB + config.correctionPreampDB)
        let output = store.outputDevices.first { $0.uid == store.selectedOutputDeviceID }
        guard output?.isBluetooth == true else { return breakdown }
        let ceiling = String(format: "%.0f dBTP", OutputLimiterCeiling.dbTP(for: output))
            .replacingOccurrences(of: "-", with: "−")
        return breakdown + " · \(ceiling) · Bluetooth headroom"
    }

    private func cancelBlend() {
        if let baseline = blendBaseline { store.restoreSoundState(baseline) }
        blendBaseline = nil
        blendPreset = nil
    }

    private func applyCurrentBlend(_ preset: Preset) {
        if let baseline = blendBaseline {
            store.registerSoundUndo(label: "Blend preset", state: baseline)
        }
        receipt = "Blended \(preset.metadata.name) at \(Int((blend * 100).rounded()))%"
        blendBaseline = nil
        blendPreset = nil
    }

}

struct SystemEQToggleView: View {
    enum Style {
        case standard
        case menuBar
    }

    @EnvironmentObject var store: EqumaczerStore
    var style: Style = .standard

    var body: some View {
        switch style {
        case .standard:
            Toggle("System EQ", isOn: binding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Enable or disable the equaliser processing. When disabled, audio passes through without EQ applied.")
        case .menuBar:
            Toggle("System EQ", isOn: binding)
                .controlSize(.small)
                .toggleStyle(.switch)
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { !store.isBypassed },
            set: { store.isBypassed = !$0 }
        )
    }
}

#Preview("EQ Window") {
    EQWindowView(showPalette: .constant(false))
        .environmentObject(PresetManagementState())
        .environmentObject(EqumaczerStore())
        .environmentObject(WindowActivationController())
}
