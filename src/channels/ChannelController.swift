// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Combine
import CoreAudio
import Foundation
import os.log

/// Owns the channel layer (layer 2): which channel is active, and
/// the factory-preset treatment staged for it (A3).
///
/// Activity comes from Core Audio's process objects — bundle ID +
/// IsRunningOutput, no permission needed — polled slowly. A
/// challenger channel must win two consecutive polls (≈5 s) before
/// the treatment switches: seconds-long integration, so brief
/// overlaps never flap the sound. The user's pin and the user's own
/// assignment edits apply immediately; the dwell exists to steady
/// the machine's picks, not to second-guess the user's.
///
/// The layer's headroom is a standalone preamp term on
/// `EQConfiguration` (see `channelPreampDB` there for why it is not
/// part of the two-layer marginal math).
@MainActor
final class ChannelController: ObservableObject {
    @Published var enabled = true { didSet { refresh() } }

    /// The remembered channel state (assignments, treatments, pin).
    @Published private(set) var state: ChannelState

    /// The channel whose treatment is currently staged.
    @Published private(set) var activeChannel: AudioChannel?

    /// Whether a call or video currently holds the stage while
    /// music is also heard (A8's trigger, computed in the poll with
    /// the classification discipline: a call needs its mic live).
    @Published private(set) var callStageActive = false
    @Published private(set) var callAppActive = false
    @Published private(set) var sceneOverride: AudioChannel?
    private(set) var manualPinRevision: UInt64 = 0

    /// Fired when `callStageActive` changes. Consumed by
    /// `AutoPauseController`.
    var onCallStageChanged: ((Bool) -> Void)?
    /// Told when the active channel really changes.
    var onActiveChannelChanged: ((AudioChannel) -> Void)?

    /// Bundle IDs heard producing output with no assignment yet —
    /// the panel's ask-once list.
    @Published private(set) var heardUnassignedIDs: [String] = []

    @Published private(set) var playingBundleIDs: [String] = []
    var appVolumesProvider: () -> [String: Float] = { [:] }
    var excludedBundleIDsProvider: () -> Set<String> = { [] }

    @Published private(set) var failedTapChannels: Set<AudioChannel> = []

    private let eqConfiguration: EQConfiguration
    private let routingCoordinator: AudioRoutingCoordinator
    private let store: ChannelStore
    private let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "ChannelController")

    private var pollTask: Task<Void, Never>?
    private var pendingChannel: AudioChannel?
    private var pendingPolls = 0

    init(
        eqConfiguration: EQConfiguration,
        routingCoordinator: AudioRoutingCoordinator,
        store: ChannelStore = ChannelStore()
    ) {
        self.eqConfiguration = eqConfiguration
        self.routingCoordinator = routingCoordinator
        self.store = store
        self.state = store.load()
    }

    func start() {
        refresh()
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.pollOnce(immediate: false)
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - User actions (the panel)

    /// Remembers an app's channel (ask-once: this is the answer).
    /// Re-evaluates immediately — the app may be playing right now.
    func assign(bundleID: String, to channel: AudioChannel) {
        state.assignments[bundleID] = channel
        persist()
        pollOnce(immediate: true)
    }

    /// Forgets a user assignment (a built-in, if any, applies again).
    func unassign(bundleID: String) {
        state.assignments.removeValue(forKey: bundleID)
        persist()
        pollOnce(immediate: true)
    }

    /// Sets the factory preset treating a channel.
    func setTreatment(_ channel: AudioChannel, presetName: String) {
        state.treatments[channel] = presetName
        persist()
        refresh()
    }

    /// Turns Dialogue mode on or off for a channel (A4). Channels
    /// that don't support it (Music, Games) refuse — the rule lives
    /// in the model (`AudioChannel.supportsDialogue`); this is its
    /// enforcement point.
    func setDialogue(_ channel: AudioChannel, enabled: Bool) {
        guard channel.supportsDialogue else { return }
        if enabled {
            state.dialogue.insert(channel)
        } else {
            state.dialogue.remove(channel)
        }
        persist()
        refresh()
    }

    /// Pins a channel (its treatment always applies) or unpins.
    func setPinned(_ channel: AudioChannel?) {
        manualPinRevision &+= 1
        sceneOverride = nil
        state.pinned = channel
        persist()
        if channel == nil { activeChannel = nil; refresh() }
        pollOnce(immediate: true)
    }

    /// Transient automation never writes the user's saved pin.
    func setSceneOverride(_ channel: AudioChannel?) {
        sceneOverride = channel
        if channel == nil { activeChannel = nil; refresh() }
        pollOnce(immediate: true)
    }

    /// Sets what happens during calls (A3). Default Lower.
    func setDuringCalls(_ mode: DuringCallsMode) {
        state.duringCalls = mode
        persist()
    }

    /// Whether the live route has a mixer that can lower sound.
    var canDuck: Bool { routingCoordinator.pipelineManager.renderPipeline?.channelMixer != nil }

    private var duckRequested = false

    /// Gain only: no tap change, no RouteSeam generation bump.
    func setDucked(_ ducked: Bool) {
        duckRequested = ducked
        routingCoordinator.pipelineManager.renderPipeline?.channelMixer?.setDucked(ducked)
    }

    func setCallCliffSaveEnabled(_ enabled: Bool) {
        state.callCliffSaveEnabled = enabled
        persist()
    }

    // MARK: - Staging

    /// Restages the active channel's treatment on layer 2. Called on
    /// channel change, treatment change, and pipeline reapply (via
    /// the routing coordinator, like the correction layer).
    func refresh() {
        failedTapChannels = routingCoordinator.pipelineManager.renderPipeline?.failedMixerChannels ?? []
        if let mixer = routingCoordinator.pipelineManager.renderPipeline?.channelMixer {
            mixer.setDucked(duckRequested)
            let stager = routingCoordinator.eqStager
            for channel in AudioChannel.allCases {
                let (preset, bands) = treatment(for: channel)
                let coefficients = stager.designedCoefficients(for: bands, count: bands.count)
                let flags = bands.map { $0.bypass }
                let preamp = min(preset?.settings.inputGain ?? 0, Float(HeadroomAnalyzer.recommendedAutoPreampDB(
                    svfCoefficients: coefficients, bypassFlags: flags, activeBandCount: bands.count,
                    sampleRate: stager.sampleRate)), 0)
                for slot in mixer.slots where slot.channel == channel {
                    slot.gainBits.store(AudioMath.dbToLinear(preamp).bitPattern, ordering: .relaxed)
                    for chain in [slot.leftEQ, slot.rightEQ] {
                        chain.stageFullUpdate(coefficients: coefficients, bypassFlags: flags,
                            activeBandCount: bands.count, layerBypass: false)
                    }
                }
            }
            for slot in mixer.slots {
                if let id = slot.bundleID {
                    slot.volumeBits.store((appVolumesProvider()[id] ?? 1).bitPattern, ordering: .relaxed)
                }
            }
            // Channel headroom is now local to each tap. The master layer is
            // skipped by the mixer callback, so it cannot treat every app twice.
            eqConfiguration.setChannelPreampDB(0)
            routingCoordinator.updateInputGain(linear: AudioMath.dbToLinear(eqConfiguration.effectiveInputGainDB))
            return
        }
        let (preset, bands) = treatment(for: activeChannel)

        let stager = routingCoordinator.eqStager
        let coefficients = stager.designedCoefficients(for: bands, count: bands.count)
        let bypassFlags = bands.map { $0.bypass }
        let analyserPreamp = HeadroomAnalyzer.recommendedAutoPreampDB(
            svfCoefficients: coefficients,
            bypassFlags: bypassFlags,
            activeBandCount: bands.count,
            sampleRate: stager.sampleRate
        )

        let previousEffective = eqConfiguration.effectiveInputGainDB
        eqConfiguration.setChannelPreampDB(min(
            preset?.settings.inputGain ?? 0,
            Float(analyserPreamp),
            0
        ))
        if eqConfiguration.effectiveInputGainDB != previousEffective {
            routingCoordinator.updateInputGain(
                linear: AudioMath.dbToLinear(eqConfiguration.effectiveInputGainDB)
            )
        }

        routingCoordinator.pipelineManager.renderPipeline?.stageFullEQUpdate(
            channel: .both,
            layerIndex: EQLayerConstants.channelLayerIndex,
            coefficients: coefficients,
            bypassFlags: bypassFlags,
            activeBandCount: bands.count,
            layerBypass: eqConfiguration.globalBypass
        )
    }

    private func treatment(for channel: AudioChannel?) -> (Preset?, [EQBandConfiguration]) {
        let preset = (enabled ? channel : nil).flatMap { channel in
            FactoryPresets.all.first { $0.metadata.name == state.treatmentName(for: channel) }
        }
        let bands = (preset?.settings.leftBands ?? []).map {
            EQBandConfiguration(frequency: $0.frequency, q: $0.q, gain: $0.gain,
                                filterType: $0.filterType, bypass: $0.bypass)
        }
        return (preset, DialogueClarity.composedBands(treatmentBands: bands,
            dialogueEnabled: (enabled ? channel : nil).map { state.dialogue.contains($0) } ?? false))
    }

    /// Resolve even idle live apps so pausing playback doesn't rebuild taps.
    func refreshTapAssignments() {
        let outputProcesses = Self.runningProcesses(selector: kAudioProcessPropertyIsRunningOutput)
        let running = Array(Set(outputProcesses.compactMap(\.bundleID))).sorted()
        if running != playingBundleIDs { playingBundleIDs = running }
        let volumes = appVolumesProvider()
        let bundleIDs = Set(ChannelResolver.builtInAssignments.keys).union(state.assignments.keys).union(running).union(volumes.keys)
        var processes: [String: [AudioObjectID]] = [:]
        var channels: [String: AudioChannel] = [:]
        for id in bundleIDs where id != Bundle.main.bundleIdentifier {
            // Keep channel taps stable while paused. App slots are released
            // as soon as output stops, and rebuilt when it resumes.
            if volumes[id] == nil || running.contains(id) {
                processes[id] = ProcessObjectResolver.objectIDs(forBundleIDs: [id])
            }
            channels[id] = ChannelResolver.channel(forBundleID: id, userAssignments: state.assignments)
        }
        let assignments = AppTapPlan.assignments(processes: processes,
            channels: channels, volumes: volumes, excluded: excludedBundleIDsProvider())
        routingCoordinator.updateChannelTapAssignments(AppTapPlan.includingUnbundledOutput(
            outputProcesses, ownProcessID: ProcessInfo.processInfo.processIdentifier, assignments: assignments))
        let failures = routingCoordinator.pipelineManager.renderPipeline?.failedMixerChannels ?? []
        if failures != failedTapChannels { failedTapChannels = failures }
    }

    // MARK: - Activity

    private func pollOnce(immediate: Bool) {
        refreshTapAssignments()
        let running = Self.runningOutputBundleIDs()
        var heard = Set<AudioChannel>()
        var unassigned: [String] = []
        for bundleID in running {
            if let channel = ChannelResolver.channel(forBundleID: bundleID, userAssignments: state.assignments) {
                heard.insert(channel)
            } else {
                unassigned.append(bundleID)
            }
        }
        let sortedUnassigned = unassigned.sorted()
        if sortedUnassigned != heardUnassignedIDs {
            heardUnassignedIDs = sortedUnassigned
        }

        let callActive = heard.contains(.calls)
        if callAppActive != callActive { callAppActive = callActive }
        updateCallStage(running: running, heard: heard)

        guard let winner = ChannelResolver.activeChannel(heard: heard, pinned: sceneOverride ?? state.pinned) else {
            // Nothing heard: the current treatment stays as it is.
            pendingChannel = nil
            pendingPolls = 0
            return
        }
        if immediate || sceneOverride != nil || state.pinned != nil {
            applyChannel(winner)
            pendingChannel = nil
            pendingPolls = 0
        } else if winner == activeChannel {
            pendingChannel = nil
            pendingPolls = 0
        } else if winner == pendingChannel {
            pendingPolls += 1
            if pendingPolls >= 2 {
                applyChannel(winner)
                pendingChannel = nil
                pendingPolls = 0
            }
        } else {
            pendingChannel = winner
            pendingPolls = 1
        }
    }

    /// The A8 stage: music is heard, and either a film app is
    /// producing output, or a calls app is producing output with
    /// its mic live (input running). Output alone never makes a
    /// call the stage — a waiting room or a notification ding is
    /// not a conversation.
    private func updateCallStage(running: [String], heard: Set<AudioChannel>) {
        var stage = false
        if heard.contains(.music) {
            let inputRunning = Self.runningInputBundleIDs()
            for bundleID in running {
                guard let channel = ChannelResolver.channel(
                    forBundleID: bundleID,
                    userAssignments: state.assignments
                ) else { continue }
                if channel == .film || (channel == .calls && inputRunning.contains(bundleID)) {
                    stage = true
                    break
                }
            }
        }
        if stage != callStageActive {
            callStageActive = stage
            onCallStageChanged?(stage)
        }
    }

    private func applyChannel(_ channel: AudioChannel) {
        guard channel != activeChannel else { return }
        activeChannel = channel
        logger.info("Active channel: \(channel.displayName, privacy: .public)")
        onActiveChannelChanged?(channel)
        refresh()
    }

    private func persist() {
        store.save(state)
    }

    // MARK: - Process enumeration

    /// Bundle IDs of every process currently running output,
    /// deduplicated, excluding this app. Core Audio process objects
    /// need no permission; a denied or failed query reads as silence.
    nonisolated static func runningOutputBundleIDs() -> [String] {
        Array(Set(runningProcesses(selector: kAudioProcessPropertyIsRunningOutput).compactMap(\.bundleID)))
    }

    /// Bundle IDs of every process currently running input (a live
    /// mic), same terms as the output enumeration.
    nonisolated static func runningInputBundleIDs() -> Set<String> {
        Set(runningProcesses(selector: kAudioProcessPropertyIsRunningInput).compactMap(\.bundleID))
    }

    nonisolated private static func runningProcesses(selector: AudioObjectPropertySelector) -> [RunningAudioProcess] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var objects = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }

        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        var result: [RunningAudioProcess] = []
        for object in objects {
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(object, &runningAddress, 0, nil, &runningSize, &running) == noErr,
                  running != 0
            else { continue }

            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &pidSize, &pid) == noErr,
                  pid > 0, pid != ownProcessID else { continue }

            var bundleAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var bundleID: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let status = AudioObjectGetPropertyData(object, &bundleAddress, 0, nil, &bundleSize, &bundleID)
            let id = bundleID?.takeRetainedValue() as String?
            // A missing or empty bundle ID is normal for command-line players.
            result.append(RunningAudioProcess(objectID: object, processID: pid,
                bundleID: status == noErr && id?.isEmpty == false ? id : nil))
        }
        return Array(result)
    }
}
