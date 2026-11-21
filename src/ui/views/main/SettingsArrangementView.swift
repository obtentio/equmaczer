// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

/// The seven Settings categories share their existing feature panes.
enum SettingsTileID: String, CaseIterable, Identifiable {
    case display, driver, channels, hearing, keys, general, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .display: return "Display"
        case .driver: return "Driver"
        case .channels: return "Channels"
        case .hearing: return "Hearing"
        case .keys: return "Keys"
        case .general: return "General"
        case .about: return "About and legal"
        }
    }
}

struct SettingsArrangementView: View {
    @EnvironmentObject var store: EqumaczerStore
    @StateObject private var driverManager = DriverManager.shared
    @AppStorage("workspace.settings") private var selected: SettingsTileID = .display

    var category: SettingsTileID? = nil
    var sceneRules: SceneRuleStore = .shared

    private var activeCategory: SettingsTileID { category ?? selected }

    var body: some View {
        HStack(alignment: .top, spacing: EQDesign.gapIn) {
            VStack(spacing: 8) {
                ForEach(SettingsTileID.allCases) { tile in miniTile(tile) }
                Spacer(minLength: 0)
            }
            .frame(width: 176)
            SettingsPanel(title: activeCategory.title, sub: "Settings", isMaster: true) {
                if activeCategory == .channels { masterContent } else { ScrollView { masterContent } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(EQDesign.gapOut)
        .preferredColorScheme(.dark)
        .tint(Color.eqG80)
        .background(Color.eqG05)
    }

    @ViewBuilder
    private var masterContent: some View {
        Group {
            switch activeCategory {
            case .display: DisplaySettingsTab()
            case .driver: DriverSettingsTab()
            case .channels: ChannelsSettingsTab(controller: store.channelController,
                cliffController: store.callCliffController, store: store, exclusionStore: store.exclusionStore, sceneRules: sceneRules)
            case .hearing: HearingSettingsTab(controller: store.hearingController, doseController: store.doseController)
            case .keys: KeysTileView()
            case .general: GeneralTileView()
            case .about: AboutTab()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func miniTile(_ tile: SettingsTileID) -> some View {
        Button {
            selected = tile
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.title)
                        .font(.eqT1)
                        .foregroundStyle(Color.eqG95)
                    Text(stateLine(tile))
                        .font(.eqT0)
                        .foregroundStyle(Color.eqG60)
                        .lineLimit(1)
                }
                Spacer()
                if needsUser(tile) {
                    Rectangle().fill(Color.eqG80).frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(activeCategory == tile ? Color.eqG20 : Color.clear)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.eqG20).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }

    /// The Driver category marks a setup problem in the same grey palette.
    private func needsUser(_ tile: SettingsTileID) -> Bool {
        guard tile == .driver else { return false }
        if case .needsUpdate = driverManager.status { return true }
        return !driverManager.isReady || store.showDriverUpdateRequired
    }

    private func stateLine(_ tile: SettingsTileID) -> String {
        switch tile {
        case .display: return store.spectrumEnabled ? "Spectrum on" : "Spectrum off"
        case .driver:
            if !driverManager.isReady { return "Missing" }
            return needsUser(.driver) ? "Needs updating" : "OK"
        case .channels: return store.channelController.activeChannel?.displayName ?? "No channel"
        case .hearing: return store.hearingController.state.enabled ? "On" : "Off"
        case .keys: return "Panic \(UserDefaults.standard.string(forKey: "keys.panic") ?? "P")"
        case .general: return "Defaults"
        case .about: return "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")"
        }
    }
}

// MARK: - Scenes and rules

struct ScenesTileView: View {
    @ObservedObject var sceneRules = SceneRuleStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rules temporarily select a channel treatment. Calls release when their audio ends; scheduled rules release at the next hour. Device rules last until another rule or a manual channel choice.")
                .font(.eqT2)
                .foregroundStyle(Color.eqG80)
            PagedList(items: Array(sceneRules.rules.indices), id: \.self, pageSize: 1) { index in
                let rule = $sceneRules.rules[index]
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enabled", isOn: rule.enabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    Picker("When", selection: rule.trigger) {
                        ForEach(SceneRule.Trigger.allCases) { trigger in
                            Text(trigger.title).tag(trigger)
                        }
                    }

                    .frame(maxWidth: .infinity)
                    if rule.wrappedValue.trigger == .hour {
                        Stepper("\(rule.wrappedValue.hour):00", value: rule.hour, in: 0...23)
                            .font(.eqT2)
                    }
                    Text("→")
                        .foregroundStyle(Color.eqG60)
                    Picker("Channel", selection: rule.channel) {
                        ForEach(AudioChannel.allCases) { channel in
                            Text(channel.displayName).tag(channel)
                        }
                    }

                    .frame(maxWidth: .infinity)
                    Button("Remove") {
                        sceneRules.removeRule(id: rule.wrappedValue.id)
                    }
                    .buttonStyle(.plain)
                    .font(.eqT1)
                    .foregroundStyle(Color.eqG60)
                }
                .padding(10)
                .background(Color.eqG10)
                .overlay(Rectangle().strokeBorder(Color.eqG20, lineWidth: 1))
            }
            Button("Add a rule") { sceneRules.addRule() }.disabled(sceneRules.rules.count >= 64)
                .buttonStyle(.plain)
                .font(.eqT1)
                .foregroundStyle(Color.eqG95)
            Text("A call outranks everything. Otherwise the latest trigger wins, and releasing returns to what you had.")
                .font(.eqT0)
                .foregroundStyle(Color.eqG60)
        }
        .padding(4)
    }
}

// MARK: - Keys

struct KeysTileView: View {
    @AppStorage("keys.compareHold") private var compareHold = true
    @AppStorage("keys.compare") private var compareKey = "C"
    @AppStorage("keys.panic") private var panicKey = "P"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            keyRow("Compare", detail: compareHold ? "Hold to hear the other side" : "Press to toggle sides") {
                HStack(spacing: 10) {
                    Toggle("Hold", isOn: $compareHold)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.eqT2)
                    KeyCaptureButton(key: Binding(get: { compareKey }, set: { if $0 != panicKey { compareKey = $0 } }))
                }
            }
            keyRow("Panic", detail: "Hold to bypass; release restores the prior state") {
                KeyCaptureButton(key: Binding(get: { panicKey }, set: { if $0 != compareKey { panicKey = $0 } }))
            }
            keyRow("Palette", detail: "Finds settings, presets and actions") {
                Text("⌘K")
                    .font(.eqT3)
                    .foregroundStyle(Color.eqG80)
            }
            Text("Compare and Panic require different keys. Command shortcuts are preserved.")
                .font(.eqT0).foregroundStyle(Color.eqG80)
            Button("Reset keys") {
                compareHold = true
                compareKey = "C"
                panicKey = "P"
            }
            .buttonStyle(.plain)
            .font(.eqT1)
            .foregroundStyle(Color.eqG60)
        }
        .padding(4)
    }

    private func keyRow<Control: View>(_ title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.eqT2).foregroundStyle(Color.eqG95)
                Text(detail).font(.eqT0).foregroundStyle(Color.eqG60)
            }
            Spacer()
            control()
        }
        .padding(10)
        .background(Color.eqG10)
        .overlay(Rectangle().strokeBorder(Color.eqG20, lineWidth: 1))
    }
}

/// A button that captures the next letter or number key press as a
/// binding. Escape cancels. The captured value is one character —
/// these are single-key bindings by design.
struct KeyCaptureButton: View {
    @Binding var key: String
    @State private var capturing = false

    var body: some View {
        Button(capturing ? "Type a key…" : key) {
            if !KeyCaptureSession.isActive { capturing = true }
        }
        .buttonStyle(.plain)
        .font(.eqT3)
        .foregroundStyle(capturing ? Color.eqG95 : Color.eqG80)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            Rectangle().fill(Color.eqG20)
        )
        .background(KeyCaptureMonitor(active: capturing) { captured in
            if let captured { key = captured }
            capturing = false
        })
    }
}

private struct KeyCaptureMonitor: NSViewRepresentable {
    let active: Bool
    let onKey: (String?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.onKey = onKey
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKey = onKey
        if active {
            context.coordinator.install()
        } else {
            context.coordinator.remove()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

    @MainActor
    final class Coordinator {
        var onKey: ((String?) -> Void)?
        private var monitor: Any?

        func install() {
            guard monitor == nil else { return }
            KeyCaptureSession.isActive = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                if event.keyCode == 53 { // Escape cancels
                    self.onKey?(nil)
                    return nil
                }
                guard ShortcutPolicy.isUnmodified(event.modifierFlags) else { return event }
                if let chars = event.charactersIgnoringModifiers?.uppercased(),
                   let c = chars.first, c.isLetter || c.isNumber {
                    self.onKey?(String(c))
                    return nil
                }
                return event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            KeyCaptureSession.isActive = false
        }


    }
}

// MARK: - General

struct GeneralTileView: View {
    @EnvironmentObject var store: EqumaczerStore
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var confirmResetAll = false
    @State private var transferNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("Start at login", detail: "Opens with your Mac") {
                Toggle("", isOn: $startAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .onChange(of: startAtLogin) { _, newValue in
                        setLogin(newValue)
                    }
            }
            if let loginError {
                Text(loginError).font(.eqT0).foregroundStyle(Color.eqG95)
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                row("Updates", detail: store.updateService.statusDetail(at: context.date)) {
                    HStack(spacing: 10) {
                        if store.updateService.isChecking {
                            ProgressView().controlSize(.small).tint(Color.eqG60)
                        }
                        if let url = store.updateService.releaseURL {
                            Button("Download") { NSWorkspace.shared.open(url) }
                        }
                        Button("Check now") {
                            Task { await store.updateService.forceCheckForUpdates() }
                        }.disabled(store.updateService.isChecking)
                    }
                }
            }
            row("Check for updates automatically", detail: "Checks GitHub Releases once a day") {
                Toggle("", isOn: Binding(get: { store.updateService.automaticChecksEnabled }, set: {
                    store.updateService.automaticChecksEnabled = $0
                    store.persistence.save(store.currentSnapshot)
                }))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
            row("Loudness compensation", detail: "Balances bass and treble at lower listening volumes") {
                Toggle("", isOn: loudnessBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            row("Auto-preamp", detail: "Reserves headroom for the combined EQ boosts") {
                Toggle("", isOn: autoPreampBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            row("EQ and routing", detail: transferNote ?? "Exports the current EQ and routing settings; excludes preset files, profiles, rules and keys") {
                HStack(spacing: 10) {
                    Button("Export") { exportSettings() }
                        .buttonStyle(.plain)
                        .font(.eqT1)
                        .foregroundStyle(Color.eqG95)
                    Button("Import") { importSettings() }
                        .buttonStyle(.plain)
                        .font(.eqT1)
                        .foregroundStyle(Color.eqG95)
                }
            }
            row("Reset General", detail: "Only the switches in this category") {
                Button("Reset") { resetTile() }
                    .buttonStyle(.plain)
                    .font(.eqT1)
                    .foregroundStyle(Color.eqG60)
            }
            row("Reset rules and keys", detail: "Clears scene rules and restores default keyboard bindings") {
                if confirmResetAll {
                    HStack(spacing: 10) {
                        Text("This cannot be undone").font(.eqT1).foregroundStyle(Color.eqG95)
                        Button("Reset") { resetEverything() }
                            .buttonStyle(.plain)
                            .font(.eqT1)
                            .foregroundStyle(Color.eqG95)
                        Button("Keep") { confirmResetAll = false }
                            .buttonStyle(.plain)
                            .font(.eqT1)
                            .foregroundStyle(Color.eqG80)
                    }
                } else {
                    Button("Reset") { confirmResetAll = true }
                        .buttonStyle(.plain)
                        .font(.eqT1)
                        .foregroundStyle(Color.eqG60)
                }
            }
        }
        .padding(4)
    }

    private func row<Control: View>(_ title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.eqT2).foregroundStyle(Color.eqG95)
                Text(detail).font(.eqT0).foregroundStyle(Color.eqG60)
            }
            Spacer()
            control()
        }
        .padding(10)
        .background(Color.eqG10)
        .overlay(Rectangle().strokeBorder(Color.eqG20, lineWidth: 1))
    }

    private var loudnessBinding: Binding<Bool> {
        Binding(get: { store.loudnessEnabled }, set: { store.loudnessEnabled = $0 })
    }

    private var autoPreampBinding: Binding<Bool> {
        Binding(get: { store.autoPreampEnabled }, set: { store.autoPreampEnabled = $0 })
    }

    private func setLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            startAtLogin = SMAppService.mainApp.status == .enabled
            loginError = SMAppService.mainApp.status == .requiresApproval ? "Enable the login item in System Settings" : nil
        } catch {
            loginError = "Login item could not be changed"
            startAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "equmaczer-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try JSONEncoder().encode(store.currentSnapshot)
            try data.write(to: url)
            transferNote = "Exported to \(url.lastPathComponent)"
        } catch {
            transferNote = "Export failed"
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importSettings(data: Data(contentsOf: url))
            transferNote = "Imported — settings applied"
        } catch { transferNote = error.localizedDescription }
    }

    private func resetTile() {
        store.updateService.automaticChecksEnabled = true
        store.persistence.save(store.currentSnapshot)
        store.loudnessEnabled = false
        store.autoPreampEnabled = true
        if startAtLogin { startAtLogin = false }
        transferNote = nil
    }

    private func resetEverything() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("keys.") || key.hasPrefix("scenes.") {
            defaults.removeObject(forKey: key)
        }
        SceneRuleStore.shared.reset()
        confirmResetAll = false
        transferNote = "Rules and keys reset"
    }
}
