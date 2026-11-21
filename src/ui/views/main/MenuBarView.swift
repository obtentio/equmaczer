import SwiftUI

enum RemotePalette {
    static let bright = Color(white: 242.0 / 255)
    static let text = Color(white: 200.0 / 255)
    static let muted = Color(white: 138.0 / 255)
    static let off = Color(white: 85.0 / 255)
    static let track = Color(white: 58.0 / 255)
}

struct MenuBarContentView: View {
    @EnvironmentObject private var store: EqumaczerStore
    @EnvironmentObject private var windowActivation: WindowActivationController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RemoteStoreView(store: store, open: {
            windowActivation.prepareToShowWindow()
            openWindow(id: "equaliser")
            NSApp.activate(ignoringOtherApps: true)
            dismiss()
        })
    }
}

private struct RemoteStoreView: View {
    @ObservedObject var store: EqumaczerStore
    @ObservedObject private var presets: PresetManager
    @ObservedObject private var pause: AutoPauseController
    @ObservedObject private var dose: DoseController
    @ObservedObject private var call: CallCliffController
    @ObservedObject private var updates: UpdateCheckService
    @ObservedObject private var driver = DriverManager.shared
    let open: () -> Void

    init(store: EqumaczerStore, open: @escaping () -> Void) {
        self.store = store
        updates = store.updateService
        presets = store.presetManager
        pause = store.autoPauseController
        dose = store.doseController
        call = store.callCliffController
        self.open = open
    }

    var body: some View {
        let state = MenuBarIconState.choose(status: store.routingStatus, isBypassed: store.isBypassed)
        let vm = PresetViewModel(store: store)
        let hasCall = call.offer != nil || call.cliffWithoutAlternative || call.restoreOffer != nil
        MenuBarRemoteView(
            state: state,
            subtitle: RemotePresentation.subtitle(state: state, paused: pause.isHoldingMusic, ducked: pause.isDucking,
                preset: vm.currentPresetName, output: RoutingViewModel(store: store).outputDeviceName),
            blockedReason: RemotePresentation.blockedReason(status: store.routingStatus, driverStatus: driver.status),
            presets: vm.mostUsedPresets.map(\.id), selectedPreset: vm.selectedPresetName,
            outputGain: Binding(get: { store.outputGain }, set: { store.updateOutputGain($0) }),
            dosePercent: (dose.week.last?.fraction ?? 0) * 100,
            hasCall: hasCall,
            updateURL: updates.releaseURL,
            recordingContent: AnyView(RecordingControls(store: store)),
            appsContent: AnyView(AppsListView(store: store, remote: true)),
            toggle: { store.isBypassed.toggle() }, selectPreset: vm.selectPreset,
            open: open, quit: { NSApplication.shared.terminate(nil) }
        ) { CallRescueNotice(controller: call, remote: true) }
    }
}

enum RemotePresentation {
    static func subtitle(state: MenuBarIconState, paused: Bool, ducked: Bool = false, preset: String, output: String) -> String {
        if state == .blocked { return "Not processing" }
        if ducked { return "Music lowered for a call" }
        if paused { return "Music paused for a call" }
        if state == .off { return "Sound passes through untouched" }
        return "\(preset) · \(output)"
    }

    static func blockedReason(status: RoutingStatus, driverStatus: DriverStatus? = nil) -> String? {
        switch status {
        case .driverNotInstalled:
            switch driverStatus {
            case .needsUpdate: "Sound is blocked. The driver needs an update."
            case .installed: "Sound is blocked. The driver is not visible to macOS."
            case .error(let reason): "Sound is blocked. \(reason)"
            default: "Sound is blocked. The driver is not installed."
            }
        case .error(let reason): "Sound is blocked. \(reason)"
        default: nil
        }
    }
}

/// The actual remote, with explicit inputs for offscreen visual verification.
struct MenuBarRemoteView<CallContent: View>: View {
    let state: MenuBarIconState
    let subtitle: String
    var blockedReason: String?
    let presets: [String]
    var selectedPreset: String?
    @Binding var outputGain: Float
    var dosePercent: Double = 0
    var hasCall = false
    var updateURL: URL?
    var recordingContent: AnyView? = nil
    var appsContent: AnyView? = nil
    var toggle: () -> Void = {}
    var selectPreset: (String) -> Void = { _ in }
    var open: () -> Void = {}
    var quit: () -> Void = {}
    @ViewBuilder var callContent: () -> CallContent

    private let background = Color(white: 20.0 / 255)
    private let line = Color(white: 46.0 / 255)
    private var dim: Double { state == .on ? 1 : 0.45 }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state == .on ? "On" : "Off")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(state == .on ? RemotePalette.bright : RemotePalette.off)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(RemotePalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
                .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("System EQ").accessibilityValue(state == .on ? "On" : "Off")

            if let blockedReason {
                rule
                VStack(alignment: .leading, spacing: 4) {
                    Text(blockedReason).foregroundStyle(Color(red: 229.0 / 255, green: 72.0 / 255, blue: 77.0 / 255))
                    Button("Open equmaczer to fix", action: open).buttonStyle(.plain).underline().foregroundStyle(RemotePalette.bright)
                }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
            if hasCall {
                rule
                callContent().padding(.horizontal, 14).padding(.vertical, 10).opacity(dim)
            }
            rule
            VStack(alignment: .leading, spacing: 2) {
                Text("Preset").font(.system(size: 11)).foregroundStyle(RemotePalette.muted).padding(.bottom, 4)
                ForEach(presets, id: \.self) { name in
                    Button { selectPreset(name) } label: {
                        HStack {
                            Text(name).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 6)
                            if name == selectedPreset { Rectangle().frame(width: 6, height: 6) }
                        }
                        .foregroundStyle(name == selectedPreset ? RemotePalette.bright : RemotePalette.muted)
                        .padding(.vertical, 3).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(name == selectedPreset ? .isSelected : [])
                }
            }.padding(.horizontal, 14).padding(.vertical, 10).opacity(dim)
            rule
            VStack(spacing: 4) {
                HStack {
                    Text("Output").font(.system(size: 11)).foregroundStyle(RemotePalette.muted)
                    Spacer()
                    Text(String(format: "%+.1f dB", outputGain)).font(.system(size: 12, weight: .medium))
                        .monospacedDigit().foregroundStyle(RemotePalette.bright)
                }
                RemoteOutputSlider(gain: $outputGain)
            }.padding(.horizontal, 14).padding(.vertical, 10).opacity(dim)
            if let recordingContent {
                rule
                recordingContent.padding(.horizontal, 14).padding(.vertical, 10)
            }
            if let appsContent {
                rule
                appsContent.padding(.horizontal, 14).padding(.vertical, 10).opacity(dim)
            }
            if dosePercent >= 80 {
                rule
                Text("dose today \(Int(dosePercent.rounded()))%")
                    .font(.system(size: 12)).foregroundStyle(RemotePalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10).opacity(dim)
            }
            if let updateURL {
                rule
                Button("Update available") { NSWorkspace.shared.open(updateURL) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(RemotePalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
            }
            rule
            HStack(spacing: 0) {
                footer("Open equmaczer", colour: RemotePalette.text, action: open)
                line.frame(width: 1)
                footer("Quit", colour: RemotePalette.muted, action: quit)
            }.fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13)).frame(width: 280).background(background)
        .overlay(Rectangle().strokeBorder(line, lineWidth: 1))
        .preferredColorScheme(.dark)
    }

    private var rule: some View { line.frame(height: 1) }
    private func footer(_ title: String, colour: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).foregroundStyle(colour).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 9).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct RemoteOutputSlider: View {
    @Binding var gain: Float
    private var fraction: CGFloat { CGFloat((gain - AudioConstants.minGain) / (AudioConstants.maxGain - AudioConstants.minGain)) }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(RemotePalette.track).frame(height: 1)
                Rectangle().fill(RemotePalette.bright).frame(width: max(0, geometry.size.width * fraction), height: 1)
                Rectangle().fill(RemotePalette.bright).frame(width: 1, height: 13)
                    .offset(x: max(0, min(geometry.size.width - 1, geometry.size.width * fraction)))
            }
            .frame(height: 24).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let position = max(0, min(1, value.location.x / max(1, geometry.size.width)))
                gain = AudioConstants.minGain + Float(position) * (AudioConstants.maxGain - AudioConstants.minGain)
            })
        }.frame(height: 24)
        .accessibilityElement().accessibilityLabel("Output")
        .accessibilityValue(String(format: "%+.1f dB", gain))
        .accessibilityAdjustableAction { direction in
            gain = AudioConstants.clampGain(gain + (direction == .increment ? 0.5 : -0.5))
        }
    }
}
