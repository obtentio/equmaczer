// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// Every entry point uses the same categories and pane implementations.
struct SettingsView: View {
    var body: some View { SettingsArrangementView() }
}

// MARK: - Shared pane pieces

/// A pane's title line: oversized mono title, primary ink, rule
/// beneath — the v2 replacement for sheet-title typography.
struct SettingsPaneTitle: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.eqT4)
                .foregroundStyle(Color.eqG95)
            Rectangle()
                .fill(Color.eqG20)
                .frame(height: 1)
        }
        .padding(.bottom, 16)
    }
}

/// A mono section label with a hairline under it.
struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .bayLabel()
            Rectangle()
                .fill(Color.eqG20)
                .frame(height: 1)
        }
    }
}

/// One settings row: label and optional caption on the left, the
/// control on the right.
struct SettingsRow<Control: View>: View {
    let label: String
    var caption: String? = nil
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.eqT2Medium)
                    .foregroundStyle(Color.eqG95)
                if let caption {
                    Text(caption)
                        .font(.eqT0)
                        .foregroundStyle(Color.eqG60)
                }
            }
            Spacer()
            control
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Display

struct DisplaySettingsTab: View {
    @EnvironmentObject var store: EqumaczerStore
    @State private var showDriverRequiredAlert = false
    @State private var showPermissionDeniedAlert = false

    private enum Mode {
        case automatic
        case manual
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            SettingsSectionHeader(title: "Recordings")
            RecordingMicrophonePicker(store: store).padding(.bottom, 14)

            SettingsSectionHeader(title: "Device selection mode")

            SettingsRow(label: "Routing mode", caption: "Automatic follows macOS Sound settings. Manual needs microphone permission.") {
                Picker("Mode", selection: Binding(
                    get: { store.manualModeEnabled ? Mode.manual : Mode.automatic },
                    set: { newValue in
                        switch newValue {
                        case .automatic:
                            if !DriverManager.shared.isReady {
                                showDriverRequiredAlert = true
                                return
                            }
                            store.switchToAutomaticMode()
                        case .manual:
                            Task {
                                let granted = await store.switchToManualMode()
                                if !granted {
                                    showPermissionDeniedAlert = true
                                }
                            }
                        }
                    }
                )) {
                    Text("Automatic").tag(Mode.automatic)
                    Text("Manual").tag(Mode.manual)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
            }

            SettingsSectionHeader(title: "Bandwidth display")
                .padding(.top, 14)

            SettingsRow(label: "Band width shows as", caption: "Q Factor is a precision value — higher is narrower. Octaves are musical intervals — higher is wider.") {
                Picker("Format", selection: $store.bandwidthDisplayMode) {
                    ForEach(BandwidthDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
            }

            SettingsSectionHeader(title: "Telemetry")
                .padding(.top, 14)

            SettingsRow(label: "Level meters", caption: "Input and output bars with true-peak readouts in the main window.") {
                PolarityToggle(isOn: store.meterStore.metersEnabled) {
                    store.meterStore.metersEnabled.toggle()
                }
            }

            SettingsRow(label: "Live spectrum", caption: "Real-time output spectrum behind the EQ curve.") {
                PolarityToggle(isOn: store.spectrumEnabled) {
                    store.spectrumEnabled.toggle()
                }
            }

            Spacer()
        }
        .alert("Driver Required", isPresented: $showDriverRequiredAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Automatic mode requires the virtual audio driver. Please install it from the Driver pane in Settings.")
        }
        .alert("Permission Required", isPresented: $showPermissionDeniedAlert) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Manual mode requires microphone permission.\n\nOpen System Settings to enable it.")
        }
    }
}

// MARK: - Driver

struct DriverSettingsTab: View {
    @EnvironmentObject var store: EqumaczerStore
    @StateObject private var driverManager = DriverManager.shared
    @State private var page: String
    @State private var showUninstallConfirm = false
    @State private var showHALPermissionDeniedAlert = false

    init(initialPage: String = "Setup") {
        _page = State(initialValue: initialPage)
    }

    /// Whether the driver lacks shared memory capability
    private var driverNeedsUpdate: Bool {
        driverManager.isReady && !driverManager.hasSharedMemoryCapability()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Driver section", selection: $page) {
                Text("Setup").tag("Setup")
                Text("Signal").tag("Signal")
                Text("Health").tag("Health")
                Text("Activity").tag("Activity")
                Text("Safety and files").tag("Safety")
            }.pickerStyle(.segmented).padding(.bottom, 12)
            if page == "Setup" {
            SettingsSectionHeader(title: "Virtual Audio Driver")

            contentView
                .padding(.vertical, 12)

            if driverManager.isInstalling {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Please wait...")
                        .font(.caption)
                        .foregroundStyle(Color.eqG60)
                }
                .padding(.bottom, 8)
            }

            if let error = driverManager.installError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.eqG95)
                    Text(error)
                        .foregroundStyle(Color.eqG95)
                        .font(.caption)
                    Spacer()
                    Button {
                        driverManager.installError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.eqG60)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 8)
            }

            SettingsSectionHeader(title: "Capture Mode")

            SettingsRow(label: "Method", caption: captureCaption) {
                Picker("Method", selection: Binding(
                    get: { store.effectiveCaptureMode },
                    set: { newMode in
                        if newMode == .halInput {
                            Task {
                                let granted = await store.requestMicPermissionAndSwitchToHALCapture()
                                if !granted {
                                    await MainActor.run {
                                        showHALPermissionDeniedAlert = true
                                    }
                                }
                            }
                        } else {
                            store.captureMode = newMode
                        }
                    }
                )) {
                    Text("Process Tap").tag(CaptureMode.processTap)
                    Text("Shared Memory").tag(CaptureMode.sharedMemory)
                    Text("HAL Input").tag(CaptureMode.halInput)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220)
                .disabled(store.manualModeEnabled)
                .opacity(store.manualModeEnabled ? 0.5 : 1.0)
            }

            SettingsRow(label: "Active route", caption: "The route actually running — the watchdog moves it when a route hears nothing") {
                Text(store.routingCoordinator.currentCaptureMode?.displayName ?? "—")
                    .font(.eqT2Medium)
                    .foregroundStyle(Color.eqG95)
            }

            if let notice = store.routingCoordinator.captureFallbackNotice {
                Text(notice)
                    .font(.eqT2)
                    .foregroundStyle(Color.eqG60)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
            }

            }
            if page == "Signal" {
                ProcessingProofSection(store: store, meterStore: store.meterStore)
            }
            if page == "Health" {
                PipelineHealthSection(store: store)
            }
            if page == "Activity" {
                ActivitySection(journal: store.activityJournal)
            }
            if page == "Safety" {
            SettingsSectionHeader(title: "Speaker Guard")

            Text("On whenever the EQ runs. A true-peak ceiling at −1 dBTP sits after the EQ, pulling boosted peaks down before they can slam the output stage or a small speaker. Bypass and Compare Flat turn it off together with the EQ — a flat comparison is a true flat. For the built-in speakers there is also a guard correction in the correction panel: it cuts the deep lows small drivers cannot reproduce, and is staged as a preview before it is kept.")
                .font(.eqT2)
                .foregroundStyle(Color.eqG60)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            SettingsSectionHeader(title: "What We Leave Behind")

            Text("The driver lives at /Library/Audio/Plug-Ins/HAL/equmaczer.driver, loaded by coreaudiod whether or not the app runs — plus the previous version’s driver if it is still there. Uninstall removes both, moves the default sound device to a real device first if one of ours holds it, and restarts coreaudiod.\n\nUninstall does not touch your data: presets in ~/Library/Application Support/equmaczer/Presets (presets saved by the previous version are moved there automatically), and settings, corrections and hearing adjustments in the app's preferences. Deleting the app and that folder removes everything.")
                .font(.eqT2)
                .foregroundStyle(Color.eqG60)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            }
            Spacer(minLength: 0)
        }
        .alert("Uninstall Driver", isPresented: $showUninstallConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Uninstall", role: .destructive) {
                Task {
                    do {
                        try await driverManager.uninstallDriver()
                    } catch {
                        driverManager.installError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Removes the equmaczer driver and the previous version’s driver if present. If either is your default sound device, the default moves to a real device first, and coreaudiod restarts. Your presets and settings are kept.")
        }
        .alert("Permission Required", isPresented: $showHALPermissionDeniedAlert) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("HAL Input capture requires microphone permission.\n\nOpen System Settings to enable it.")
        }
    }

    private var captureCaption: String {
        if store.manualModeEnabled {
            return "Capture mode is not available in manual mode."
        }
        if driverNeedsUpdate {
            return "Using HAL Input because your driver version doesn't support shared memory. Update the driver to enable Shared Memory."
        }
        return "Process Tap needs no driver; it asks for audio-capture permission. Shared Memory needs the driver, no microphone permission, no indicator. HAL Input needs permission and shows the microphone indicator."
    }

    @ViewBuilder
    private var contentView: some View {
        switch driverManager.status {
        case .notInstalled:
            notInstalledView
        case .installed(let version):
            installedView(version: version)
        case .needsUpdate(let current, let bundled):
            needsUpdateView(current: current, bundled: bundled)
        case .error(let message):
            errorView(message: message)
        }
    }

    private var notInstalledView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.eqG80)
                    .frame(width: 8, height: 8)
                Text("Driver not installed")
                    .font(.eqT2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.eqG95)
                Spacer()
                Button("Install Driver") {
                    Task {
                        do {
                            try await driverManager.installDriver()
                        } catch {
                            driverManager.installError = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(driverManager.isInstalling)
            }
            Text("Install the driver to route audio through the equaliser.")
                .font(.caption)
                .foregroundStyle(Color.eqG60)
        }
    }

    private func installedView(version: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.eqG95)
                    .frame(width: 8, height: 8)
                Text("Driver installed")
                    .font(.eqT2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.eqG95)
                Text("v\(version)")
                    .font(.eqT2Medium)
                    .foregroundStyle(Color.eqG60)
                Spacer()
                Button("Uninstall", role: .destructive) {
                    showUninstallConfirm = true
                }
                .disabled(driverManager.isInstalling)
                .buttonStyle(.bordered)
            }
            if let sampleRate = driverManager.driverSampleRate {
                HStack(spacing: 8) {
                    Text("Sample Rate")
                        .font(.caption)
                        .foregroundStyle(Color.eqG60)
                    Text("\(Int(sampleRate).formatted()) Hz")
                        .font(.eqT2Medium)
                        .foregroundStyle(Color.eqG95)
                }
            }
            Text("The driver is ready to use.")
                .font(.caption)
                .foregroundStyle(Color.eqG60)
        }
    }

    private func needsUpdateView(current: String, bundled: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.eqG80)
                    .frame(width: 8, height: 8)
                Text("Update available")
                    .font(.eqT2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.eqG95)
                Text(current == bundled ? "v\(current) — older build" : "v\(current) → v\(bundled)")
                    .font(.eqT2Medium)
                    .foregroundStyle(Color.eqG60)
                Spacer()
                Button("Update Driver") {
                    Task {
                        do {
                            try await driverManager.installDriver()
                        } catch {
                            driverManager.installError = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(driverManager.isInstalling)

                Button("Uninstall", role: .destructive) {
                    showUninstallConfirm = true
                }
                .disabled(driverManager.isInstalling)
                .buttonStyle(.bordered)
            }
            Text(updateMessage(for: current, bundled: bundled))
                .font(.caption)
                .foregroundStyle(Color.eqG60)
        }
    }

    /// Minimum driver version that supports shared memory capture.
    private static let sharedMemoryMinVersion = "1.1.0"

    /// Returns the appropriate update message based on the installed version.
    /// Versions below 1.1.0 don't support shared memory capture.
    private func updateMessage(for currentVersion: String, bundled: String) -> String {
        if currentVersion == bundled {
            return "The installed driver carries the same version number but predates this build of the app — it still runs under the driver's old identity. Update to replace it with the driver this app ships."
        }
        if currentVersion.compare(Self.sharedMemoryMinVersion, options: .numeric) == .orderedAscending {
            return "The current installed version does not support the \"Shared Memory\" capture mode. Update for improved audio routing without requiring microphone permission."
        } else {
            return "A newer version is available. Update to get the latest features and fixes."
        }
    }

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.eqG95)
                    .frame(width: 8, height: 8)
                Text("Error")
                    .font(.eqT2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.eqG95)
                Spacer()
                Button("Retry") {
                    driverManager.checkInstallationStatus()
                }
                .buttonStyle(.borderedProminent)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.eqG60)
        }
    }
}

// MARK: - About

struct AboutTab: View {
    @EnvironmentObject var store: EqumaczerStore
    @StateObject private var driverManager = DriverManager.shared
    @State private var showingLegal = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private var driverVersion: String? {
        switch driverManager.status {
        case .installed(let version): version
        case .needsUpdate(let current, _): current
        default: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            HStack(spacing: 14) {
                DotArcMark(cell: 6)
                    .padding(4)
                    .overlay(
                        Rectangle()
                            .strokeBorder(Color.eqG20, lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text("equmaczer")
                        .font(.eqT4)
                        .foregroundStyle(Color.eqG95)
                    Text("Version \(appVersion) (\(buildVersion))")
                        .font(.eqT2)
                        .foregroundStyle(Color.eqG80)
                    Text("Owner: obtentio")
                        .font(.eqT2)
                        .foregroundStyle(Color.eqG60)
                    if let version = driverVersion {
                        Text("Driver version: \(version)")
                            .font(.eqT2)
                            .foregroundStyle(Color.eqG60)
                    }
                }
                Spacer()
            }
            .padding(.bottom, 14)

            SettingsSectionHeader(title: "Credits")

            SettingsRow(label: "Developer") {
                Text("obtentio")
                    .font(.eqT2Medium)
                    .foregroundStyle(Color.eqG95)
            }

            SettingsSectionHeader(title: "Legal")
                .padding(.top, 14)

            SettingsRow(label: "Open Source Acknowledgements") {
                Button("View") { showingLegal = true }
                    .buttonStyle(.plain)
                    .font(.eqT1)
                    .foregroundStyle(Color.eqG00)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.eqG95)
            }

            Spacer()

            Text("© obtentio")
                .font(.eqT0)
                .foregroundStyle(Color.eqG60)
                .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showingLegal) {
            LegalAcknowledgementsView()
        }
    }
}
