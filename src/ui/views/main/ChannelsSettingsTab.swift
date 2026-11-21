import CoreAudio
// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Channels pane (A3): what each channel sounds like, which
/// channel is live, and which apps belong where. Ask-once lives
/// here: apps heard producing sound with no assignment are listed
/// until the user gives them a channel once — the answer is
/// remembered, and no prompt ever interrupts the listening.
struct ChannelsSettingsTab: View {
    @ObservedObject var controller: ChannelController
    @ObservedObject var cliffController: CallCliffController
    @ObservedObject var store: EqumaczerStore
    @ObservedObject var exclusionStore: ExclusionStore
    var sceneRules: SceneRuleStore = .shared

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if geometry.size.width >= 960 {
                    HStack(alignment: .top, spacing: 20) {
                        channelSection.frame(maxWidth: .infinity)
                        appsSection.frame(maxWidth: .infinity)
                        rulesSection.frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        channelSection
                        appsSection
                        rulesSection
                    }
                }
            }
        }
        .frame(minHeight: 570)
    }

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "Channels")
            SettingsRow(label: "Active channel") {
                Text(controller.activeChannel?.displayName ?? "—")
                    .font(.eqT2Medium)
                    .foregroundStyle(Color.eqG95)
            }

            SettingsRow(label: "Pin", caption: "A pinned channel always applies") {
                Picker("", selection: pinBinding) {
                    Text("Auto").tag(nil as AudioChannel?)
                    ForEach(AudioChannel.allCases) { channel in
                        Text(channel.displayName).tag(channel as AudioChannel?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
            }

            SettingsRow(
                label: "During calls",
                caption: CallDuckPolicy.caption(for: controller.state.duringCalls)
            ) {
                Picker("During calls", selection: duringCallsBinding) {
                    Text("Lower to 15%").tag(DuringCallsMode.lower)
                    Text("Pause").tag(DuringCallsMode.pause)
                    Text("Nothing").tag(DuringCallsMode.nothing)
                }.labelsHidden().pickerStyle(.menu)
            }

            if controller.state.duringCalls == .lower, !controller.canDuck, case .active = store.routingStatus {
                Text(CallDuckPolicy.driverNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsRow(
                label: "Call-cliff save",
                caption: "When a call drops a Bluetooth headset to voice quality, offer the switch below. Call apps that follow the system default microphone let go of the headset, and its music quality returns."
            ) {
                Toggle("", isOn: cliffBinding)
                    .labelsHidden()
            }

            if let offer = cliffController.offer {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(offer.headsetName) has dropped to call quality — the call is using its microphone.")
                        .font(.eqT2)
                        .foregroundStyle(Color.eqG95)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Switch microphone to \(offer.microphone.name)") {
                        cliffController.switchMicrophone()
                    }
                    .font(.eqT2)
                }
                .padding(.vertical, 8)
            }

            if cliffController.cliffWithoutAlternative {
                Text("Your headset has dropped to call quality, and there is no other microphone to switch to.")
                    .font(.eqT2)
                    .foregroundStyle(Color.eqG60)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            }

            if let restore = cliffController.restoreOffer {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The call is over — the microphone is still set to the one the rescue chose.")
                        .font(.eqT2)
                        .foregroundStyle(Color.eqG95)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Switch microphone back to \(restore.name)") {
                        cliffController.switchBack()
                    }
                    .font(.eqT2)
                }
                .padding(.vertical, 8)
            }


            SettingsSectionHeader(title: "Treatments")
            ForEach(AudioChannel.allCases) { channel in
                SettingsRow(
                    label: channel.displayName,
                    caption: controller.failedTapChannels.contains(channel) ? "Tap unavailable — channel processing silent" : (controller.activeChannel == channel ? "ACTIVE" : nil)
                ) {
                    Picker("", selection: treatmentBinding(channel)) {
                        ForEach(FactoryPresets.all, id: \.metadata.name) { preset in
                            Text(preset.metadata.name).tag(preset.metadata.name)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }
                if channel.supportsDialogue {
                    SettingsRow(label: "Dialogue", caption: "Speech clarity — \(channel.displayName)") {
                        Toggle("", isOn: dialogueBinding(channel))
                            .labelsHidden()
                    }
                }
            }

        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "Apps")
                let ids = Array(Set(controller.state.assignments.keys).union(ChannelResolver.builtInAssignments.keys).union(controller.heardUnassignedIDs).union(exclusionStore.bundleIDs).union(store.appVolumes.keys).union(controller.playingBundleIDs)).sorted()
                PagedList(items: ids, id: \.self, pageSize: 4) { bundleID in
                    VStack(alignment: .leading, spacing: 4) {
                        SettingsRow(label: Self.appName(forBundleID: bundleID), caption: bundleID) {
                            Menu((controller.state.assignments[bundleID] ?? ChannelResolver.builtInAssignments[bundleID])?.displayName ?? "Assign") {
                                ForEach(AudioChannel.allCases) { channel in
                                    Button(channel.displayName) { controller.assign(bundleID: bundleID, to: channel) }
                                }
                                Button("Unassign") { controller.unassign(bundleID: bundleID) }
                            }
                        }
                        Toggle("Skip EQ", isOn: Binding(get: { exclusionStore.contains(bundleID) }, set: { skip in
                            if skip { store.excludeApp(bundleID: bundleID, name: Self.appName(forBundleID: bundleID)) }
                            else { store.includeApp(bundleID: bundleID) }
                        })).toggleStyle(.checkbox).font(.eqT2).tint(Color.eqG80)
                        AppVolumeSlider(store: store, bundleID: bundleID)
                    }
                }
                AppVolumeNotice(store: store)
                Menu("Add app…") {
                    ForEach(AudioChannel.allCases) { channel in
                        Button("Add to \(channel.displayName)") { pickApp(for: channel) }
                    }
                }
                Button("Exclude app…") { chooseAppToExclude() }
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "Rules")
            ScenesTileView(sceneRules: sceneRules)
        }
    }

    private var pinBinding: Binding<AudioChannel?> {
        Binding(
            get: { controller.state.pinned },
            set: { controller.setPinned($0) }
        )
    }

    private var duringCallsBinding: Binding<DuringCallsMode> {
        Binding(
            get: { controller.state.duringCalls },
            set: { controller.setDuringCalls($0) }
        )
    }

    private var cliffBinding: Binding<Bool> {
        Binding(
            get: { controller.state.callCliffSaveEnabled },
            set: { controller.setCallCliffSaveEnabled($0) }
        )
    }

    private func treatmentBinding(_ channel: AudioChannel) -> Binding<String> {
        Binding(
            get: { controller.state.treatmentName(for: channel) },
            set: { controller.setTreatment(channel, presetName: $0) }
        )
    }

    private func dialogueBinding(_ channel: AudioChannel) -> Binding<Bool> {
        Binding(
            get: { controller.state.dialogue.contains(channel) },
            set: { controller.setDialogue(channel, enabled: $0) }
        )
    }

    private func assignmentBinding(_ bundleID: String) -> Binding<AudioChannel> {
        Binding(
            get: {
                controller.state.assignments[bundleID]
                    ?? ChannelResolver.builtInAssignments[bundleID]
                    ?? .music
            },
            set: { controller.assign(bundleID: bundleID, to: $0) }
        )
    }

    // MARK: - Helpers

    private func pickApp(for channel: AudioChannel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose the app to assign to \(channel.displayName)."
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier
        else { return }
        controller.assign(bundleID: bundleID, to: channel)
    }

    /// D2: pick any app (a DAW that is not running, say) to add
    /// to the never-process list.
    private func chooseAppToExclude() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose the app equmaczer should never process."
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier
        else { return }
        store.excludeApp(bundleID: bundleID, name: Self.appName(forBundleID: bundleID))
    }

    static func appName(forBundleID bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }
        // Helpers (com.apple.WebKit.GPU) play for an app: name the app.
        let owners = owningApps(forBundleID: bundleID).compactMap(\.localizedName)
        return owners.isEmpty ? bundleID : owners.joined(separator: ", ")
    }

    static func appIcon(forBundleID bundleID: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return owningApps(forBundleID: bundleID).first?.icon
    }

    /// The apps responsible for a helper process's audio, via its process objects' PIDs.
    private static func owningApps(forBundleID bundleID: String) -> [NSRunningApplication] {
        guard let responsible else { return [] }
        var seen = Set<pid_t>()
        let objects = ProcessObjectResolver.objectIDs(forBundleIDs: [bundleID])
        // Several apps share a helper id; name only the ones playing right now.
        let playing = objects.filter { object in
            var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &running) == noErr && running != 0
        }
        return (playing.isEmpty ? objects : playing).compactMap { object in
            var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = 0
            var size = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr else { return nil }
            let owner = responsible(pid)
            guard owner > 0, owner != pid, seen.insert(owner).inserted,
                  let app = NSRunningApplication(processIdentifier: owner), app.bundleURL != nil else { return nil }
            return app
        }
    }

    // shortcut: private libsystem call (stable since 10.14, used by audio routers); nil if it ever disappears.
    private static let responsible: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()
}
