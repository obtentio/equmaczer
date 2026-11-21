// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import CoreAudio
import Foundation
import os

/// Watches for the call cliff (B4) and offers the rescue. Polls on
/// the channel cadence while the user has opted in. The switch
/// itself is always a button press: this controller changes the
/// system default input only from `switchMicrophone()` /
/// `switchBack()`, never from the poll.
///
/// The rescue's limit, kept in the pane's wording: call apps that
/// follow the system default input let go of the headset when the
/// default moves; apps with their own microphone pickers keep
/// their choice.
@MainActor
final class CallCliffController: ObservableObject {
    struct Offer: Equatable {
        let headsetName: String
        let microphone: AudioDevice
    }

    @Published private(set) var microphoneCandidates: [AudioDevice] = []
    @Published private(set) var cliffHeadsetName: String?
    private var headsetUID: String?
    private var rememberedMicrophones: [String: String] = UserDefaults.standard.dictionary(forKey: "callCliff.microphones") as? [String: String] ?? [:]

    @Published private(set) var offer: Offer?
    @Published private(set) var cliffWithoutAlternative = false
    @Published private(set) var restoreOffer: AudioDevice?

    private let deviceManager: DeviceManager
    private let routingCoordinator: AudioRoutingCoordinator
    private let channelController: ChannelController
    private var timer: Timer?
    private var switchedFrom: AudioDevice?
    private var switchedToUID: String?
    private var clearPolls = 0
    private let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "CallCliff")

    init(
        deviceManager: DeviceManager,
        routingCoordinator: AudioRoutingCoordinator,
        channelController: ChannelController
    ) {
        self.deviceManager = deviceManager
        self.routingCoordinator = routingCoordinator
        self.channelController = channelController
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    // MARK: - The rescue (button presses only)

    func switchMicrophone() {
        guard let offer else { return }
        let previousInput = currentDefaultInput()
        guard setDefaultInput(offer.microphone) else { return }
        if let headsetUID {
            rememberedMicrophones[headsetUID] = offer.microphone.uid
            UserDefaults.standard.set(rememberedMicrophones, forKey: "callCliff.microphones")
        }
        switchedFrom = previousInput
        switchedToUID = offer.microphone.uid
        clearPolls = 0
        self.offer = nil
        cliffWithoutAlternative = false
        logger.info("Call-cliff save: microphone switched to \(offer.microphone.name, privacy: .public)")
    }

    func selectMicrophone(uid: String) {
        guard let current = offer, let microphone = microphoneCandidates.first(where: { $0.uid == uid }) else { return }
        offer = Offer(headsetName: current.headsetName, microphone: microphone)
    }

    func switchBack() {
        guard let restoreOffer else { return }
        guard setDefaultInput(restoreOffer) else { return }
        logger.info("Call-cliff save: microphone restored to \(restoreOffer.name, privacy: .public)")
        switchedFrom = nil
        switchedToUID = nil
        self.restoreOffer = nil
        clearPolls = 0
    }

    // MARK: - Poll

    private func tick() {
        guard channelController.state.callCliffSaveEnabled else {
            offer = nil
            cliffWithoutAlternative = false
            return
        }
        let callLive = probeCallLive()
        updateRestore(callLive: callLive)
        guard switchedFrom == nil else {
            // Already rescued; don't re-offer mid-call.
            offer = nil
            cliffWithoutAlternative = false
            return
        }
        let facts = routingCoordinator.healthFacts()
        let outputDevice = routingCoordinator.selectedOutputDeviceID
            .flatMap { deviceManager.device(forUID: $0) }
        let isBluetooth = outputDevice.map(CallCliff.isBluetooth) ?? false
        if CallCliff.isCliff(
            callLive: callLive,
            outputIsBluetooth: isBluetooth,
            outputRateHz: facts.outputRate
        ) {
            headsetUID = outputDevice?.uid
            cliffHeadsetName = outputDevice?.name
            microphoneCandidates = CallCliff.microphoneCandidates(inputDevices: deviceManager.inputDevices, excludingUID: outputDevice?.uid)
            if let microphone = CallCliff.preferredMicrophone(candidates: microphoneCandidates, rememberedUID: headsetUID.flatMap { rememberedMicrophones[$0] }) {
                offer = Offer(
                    headsetName: outputDevice?.name ?? "Your headset",
                    microphone: microphone
                )
                cliffWithoutAlternative = false
            } else {
                offer = nil
                cliffWithoutAlternative = true
            }
        } else {
            offer = nil
            cliffWithoutAlternative = false
        }
    }

    /// A call is live when a calls-channel app is producing output
    /// with its input running (the A8 probe pair, without A8's
    /// music-heard condition — auto-pause may already have
    /// silenced the music, and the cliff matters anyway).
    private func probeCallLive() -> Bool {
        let inputs = ChannelController.runningInputBundleIDs()
        guard !inputs.isEmpty else { return false }
        return ChannelController.runningOutputBundleIDs().contains { bundleID in
            inputs.contains(bundleID)
                && ChannelResolver.channel(
                    forBundleID: bundleID,
                    userAssignments: channelController.state.assignments
                ) == .calls
        }
    }

    private func updateRestore(callLive: Bool) {
        guard switchedFrom != nil else { return }
        // If the default input is no longer the microphone we
        // chose, someone else owns the setting now — retire the
        // restore offer quietly.
        if let current = currentDefaultInput(), current.uid != switchedToUID {
            switchedFrom = nil
            switchedToUID = nil
            restoreOffer = nil
            clearPolls = 0
            return
        }
        if callLive {
            clearPolls = 0
            restoreOffer = nil
            return
        }
        clearPolls += 1
        if clearPolls >= 2, let switchedFrom {
            restoreOffer = switchedFrom
        }
    }

    // MARK: - System default input

    private func currentDefaultInput() -> AudioDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        ) == noErr else { return nil }
        return deviceManager.inputDevices.first { $0.id == deviceID }
    }

    private func setDefaultInput(_ device: AudioDevice) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = device.id
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID
        ) == noErr
    }
}
