// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

// MARK: - Cleanup Delegate

@MainActor
final class AppCleanupDelegate: NSObject, NSApplicationDelegate {
    private weak var store: EqumaczerStore?

    func setStore(_ store: EqumaczerStore) {
        self.store = store
    }
}

// MARK: - Main App

@main
struct EqumaczerMain: App {
    @Environment(\.openWindow) private var openWindow
    @State private var showPalette = false
    @StateObject private var store = EqumaczerStore()
    @StateObject private var presetManagement = PresetManagementState()
    @StateObject private var windowActivation = WindowActivationController()
    @NSApplicationDelegateAdaptor(AppCleanupDelegate.self) var appDelegate

    init() {
        // One-time settings migration from a legacy defaults domain,
        // when the upgrade script supplies one (Slice 4). Runs before
        // the store exists; a no-op on every ordinary launch.
        IdentityMigrationService.migrateIfNeeded()

        if CommandLine.arguments.contains("--stress-benchmark") {
            exit(LayeredRenderBenchmark.run() ? 0 : 1)
        }
        if CommandLine.arguments.contains("--benchmark") {
            let report = DSPBenchmarkSuite.runAll()
            print(report.formattedSummary())
            exit(report.allCriteriaPassed ? 0 : 1)
        }
        // IMPORTANT: Do NOT access @StateObject (self.store) here.
        // SwiftUI initializes @StateObject AFTER init() completes.
        // Accessing it in init() causes SwiftUI to create two instances.
        // Wire appDelegate.setStore(store) in body using .onAppear instead.

        // Note: Microphone permission is NOT requested here.
        // It's only requested when needed (HAL input capture mode or manual mode).
        // Shared memory capture (default) does NOT require microphone permission.
    }

    var body: some Scene {
        // Main EQ settings window (hidden by default, opened on demand)
        Window("equmaczer", id: "equaliser") {
            EQWindowView(showPalette: $showPalette)
                .environmentObject(presetManagement)
                .environmentObject(store)
                .environmentObject(windowActivation)
                .environmentObject(store.sceneEngine)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultPosition(.center)
        .defaultSize(width: 1120, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                PresetManagementMenu(presetName: store.presetManager.selectedPresetName)
                    .environmentObject(presetManagement)
            }
            CommandGroup(replacing: .help) {
                Button("Search everything") {
                    openWindow(id: "equaliser")
                    showPalette = true
                }.keyboardShortcut("k", modifiers: .command)
            }
            CommandGroup(replacing: .undoRedo) {
                Button(store.undoLabel.map { "Undo " + $0 } ?? "Undo") { store.undoLastAction() }
                    .keyboardShortcut("z", modifiers: .command).disabled(store.undoLabel == nil)
                Button(store.redoLabel.map { "Redo " + $0 } ?? "Redo") { store.redoLastAction() }
                    .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(store.redoLabel == nil)
                Divider()
                Button("Flatten") { store.flattenBands() }
            }
            // Cmd+B: Toggle bypass
            CommandGroup(replacing: .toolbar) {
                Button("Toggle Bypass") {
                    store.isBypassed.toggle()
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Save Preset") {
                    NotificationCenter.default.post(name: .savePresetShortcut, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }

        // A template status item reflects the remote's transport and power state.
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(store)
                .environmentObject(windowActivation)
                .onAppear {
                    windowActivation.launchAsMenuBarApp()
                    // MenuBarExtra is always visible, so this will always fire.
                    // Wire up appDelegate reference after @StateObject is initialized.
                    appDelegate.setStore(store)
                    store.sceneEngine.start(store: store)
                }
        } label: {
            Image(nsImage: MenuBarIconState.choose(status: store.routingStatus, isBypassed: store.isBypassed).image())
                .accessibilityLabel("equmaczer")
        }
        .menuBarExtraStyle(.window)

        // Settings window (Cmd+,)
        Settings {
            SettingsArrangementView()
                .frame(minWidth: 832, minHeight: 680)
                .environmentObject(store)
                .environmentObject(windowActivation)
        }
        .defaultSize(width: 1024, height: 720)
        .windowResizability(.contentMinSize)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let savePresetShortcut = Notification.Name("savePresetShortcut")
}
