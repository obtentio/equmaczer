import XCTest
import Atomics
import CoreAudio
@testable import equmaczer

final class AppVolumeMixerTests: XCTestCase {
    private let app = ChannelTapAssignment(channel: .music, objectIDs: [11], bundleID: "test.music")
    private func feed(_ slot: ChannelMixerSlot, left: Float = 1, right: Float = -0.5, frames: Int = 64) {
        let l = [Float](repeating: left, count: frames)
        let r = [Float](repeating: right, count: frames)
        l.withUnsafeBufferPointer { l in
            r.withUnsafeBufferPointer { r in slot.write(left: l.baseAddress!, right: r.baseAddress!, frameCount: frames) }
        }
    }

    func testFortyPercentBothEarsAndOtherChannelUntouched() {
        let mixer = ChannelMixer(maxFrameCount: 64, appAssignments: [app])
        let slot = mixer.appSlot(for: "test.music")!
        slot.volumeBits.store(Float(0.4).bitPattern, ordering: .relaxed)
        mixer.activate(assignments: [app, ChannelTapAssignment(channel: .calls, objectIDs: [22])])
        for _ in 0..<4 {
            feed(slot)
            feed(mixer.slot(for: .calls), left: 0.2, right: 0.3)
            mixer.process(frameCount: 64)
        }
        for frame in 0..<64 {
            XCTAssertEqual(mixer.output(0)[frame], 0.6, accuracy: 1e-6)
            XCTAssertEqual(mixer.output(1)[frame], 0.1, accuracy: 1e-6)
        }
    }

    func testVolumeRampBoundAcrossCallbacksAndRetargetingInBypass() {
        let mixer = ChannelMixer(maxFrameCount: 64, appAssignments: [app])
        let slot = mixer.appSlot(for: "test.music")!
        mixer.activate(assignments: [app])
        var previous: Float = 1
        for target: Float in [0, 1, 0.4, 0.8] {
            slot.volumeBits.store(target.bitPattern, ordering: .relaxed)
            for _ in 0..<4 {
                feed(slot, right: 1)
                mixer.process(frameCount: 64, treated: false)
                for frame in 0..<64 {
                    let value = mixer.output(0)[frame]
                    XCTAssertLessThanOrEqual(abs(value - previous), 1 / Float(ChannelMixer.volumeRampFrames) + 1e-7)
                    XCTAssertEqual(value, mixer.output(1)[frame])
                    previous = value
                }
            }
            XCTAssertEqual(previous, target, accuracy: 1e-6)
        }
    }

    func testNoAllocationStorageReusedTenThousandAppProcesses() {
        let mixer = ChannelMixer(maxFrameCount: 64, appAssignments: [app])
        mixer.activate(assignments: [app])
        let slot = mixer.appSlot(for: "test.music")!
        let coefficient = SVFCoefficients(biquad: BiquadMath.calculateCoefficients(
            type: .lowShelf, sampleRate: 48000, frequency: 500, q: 0.7, gain: -6))
        for chain in [slot.leftEQ, slot.rightEQ] {
            chain.stageFullUpdate(coefficients: [coefficient], bypassFlags: [false], activeBandCount: 1, layerBypass: false)
        }
        let left = mixer.output(0), right = mixer.output(1)
        let slotLeft = slot.left, slotRight = slot.right
        let signal = [Float](repeating: 0.1, count: 64)
        signal.withUnsafeBufferPointer { signal in
            for i in 0..<10_000 {
                slot.volumeBits.store(Float(i % 2 == 0 ? 0.4 : 0.8).bitPattern, ordering: .relaxed)
                slot.write(left: signal.baseAddress!, right: signal.baseAddress!, frameCount: 64)
                mixer.process(frameCount: 64)
                XCTAssertEqual(mixer.output(0), left)
                XCTAssertEqual(mixer.output(1), right)
                XCTAssertEqual(slot.left, slotLeft)
                XCTAssertEqual(slot.right, slotRight)
            }
        }
    }

    func testAtomicGainPublicationOverlapsRendering() async {
        let mixer = ChannelMixer(maxFrameCount: 64, appAssignments: [app])
        mixer.activate(assignments: [app])
        let slot = mixer.appSlot(for: "test.music")!
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for i in 0..<10_000 { slot.volumeBits.store((Float(i % 101) / 100).bitPattern, ordering: .relaxed) }
            }
            group.addTask {
                for _ in 0..<10_000 { mixer.process(frameCount: 64) }
            }
        }
        XCTAssertTrue(mixer.output(0)[0].isFinite)
    }

    func testAppReceivesItsChannelsEQAndSkipEQStaysOutsideSum() {
        let mixer = ChannelMixer(maxFrameCount: 64, appAssignments: [app])
        let slot = mixer.appSlot(for: "test.music")!
        mixer.activate(assignments: [app])
        slot.gainBits.store(Float(0.5).bitPattern, ordering: .relaxed)
        feed(slot)
        mixer.process(frameCount: 64)
        XCTAssertEqual(mixer.output(0)[63], 0.5)
        let skipped = ChannelTapAssignment(channel: .music, objectIDs: [22], bundleID: "skip", skipEQ: true)
        let bypassMixer = ChannelMixer(maxFrameCount: 64, appAssignments: [skipped])
        bypassMixer.activate(assignments: [skipped])
        let bypassSlot = bypassMixer.appSlot(for: "skip")!
        bypassSlot.gainBits.store(Float(0).bitPattern, ordering: .relaxed)
        feed(bypassSlot)
        bypassMixer.process(frameCount: 64)
        XCTAssertEqual(bypassMixer.output(0)[63], 0)
        bypassMixer.addSkipped(left: bypassMixer.output(0), right: bypassMixer.output(1), frameCount: 64)
        XCTAssertEqual(bypassMixer.output(0)[63], 1)
        XCTAssertEqual(bypassMixer.output(1)[63], -0.5)
    }
}

final class AppTapPlanTests: XCTestCase {
    func testRunningProcessWithoutBundleIDAppearsInDefaultAssignment() {
        let plan = AppTapPlan.includingUnbundledOutput([
            RunningAudioProcess(objectID: 11, processID: 101, bundleID: nil),
            RunningAudioProcess(objectID: 12, processID: 102, bundleID: ""),
            RunningAudioProcess(objectID: 22, processID: 103, bundleID: "test.app")
        ], ownProcessID: 100, assignments: [ChannelTapAssignment(channel: .music, objectIDs: [33])])
        XCTAssertEqual(plan, [ChannelTapAssignment(channel: .music, objectIDs: [11, 12, 33])])
    }

    func testOwnProcessNeverAppearsInUnbundledAssignment() {
        for bundleID: String? in [nil, "", "com.obtentio.equmaczer"] {
            let plan = AppTapPlan.includingUnbundledOutput([
                RunningAudioProcess(objectID: 11, processID: 100, bundleID: bundleID)
            ], ownProcessID: 100, assignments: [])
            XCTAssertTrue(plan.isEmpty)
        }
    }

    func testGlobalModeDoesNotSwitchToMixerForTransientUnbundledProcess() {
        let plan = AppTapPlan.includingUnbundledOutput([
            RunningAudioProcess(objectID: 44, processID: 202, bundleID: nil)
        ], ownProcessID: 100, assignments: [])
        XCTAssertTrue(plan.isEmpty)
    }

    func testVolumeAppIsOnlyInItsOwnTapAndHundredPercentKeepsChannelTap() {
        let plan = AppTapPlan.assignments(processes: ["a": [11, 12], "b": [22]],
            channels: ["a": .music, "b": .music], volumes: ["a": 0.4], excluded: [])
        XCTAssertEqual(plan, [ChannelTapAssignment(channel: .music, objectIDs: [22]),
            ChannelTapAssignment(channel: .music, objectIDs: [11, 12], bundleID: "a")])
        let normal = AppTapPlan.assignments(processes: ["a": [11], "b": [22]],
            channels: ["a": .music, "b": .music], volumes: [:], excluded: [])
        XCTAssertEqual(normal, [ChannelTapAssignment(channel: .music, objectIDs: [11, 22])])
    }
    func testExcludedAppCanHaveVolumeWithoutEQAndUnknownAppHasNoChannelTreatment() {
        let plan = AppTapPlan.assignments(processes: ["a": [11], "b": [22], "c": [33]],
            channels: ["a": .music, "c": .music], volumes: ["a": 0.4, "b": 0.5], excluded: ["a", "c"])
        XCTAssertEqual(plan.count, 2)
        XCTAssertTrue(plan[0].skipEQ)
        XCTAssertFalse(plan[1].treatsChannel)
    }
    func testSlotCapIsDeterministicAndStoragePresized() {
        let processes = Dictionary(uniqueKeysWithValues: (0..<20).map { ("app\($0)", [UInt32($0 + 1)]) })
        let volumes = Dictionary(uniqueKeysWithValues: processes.keys.map { ($0, Float(0.4)) })
        let plan = AppTapPlan.assignments(processes: processes, channels: [:], volumes: volumes, excluded: [])
        XCTAssertEqual(plan.count, 16)
        let mixer = ChannelMixer(maxFrameCount: 64, appAssignments: plan)
        XCTAssertEqual(mixer.slots.count, AudioChannel.allCases.count + 16)
        XCTAssertEqual(plan.compactMap(\.bundleID), Array(processes.keys.sorted().prefix(16)))
    }
    func testPersistenceRoundTripAndInvalidValuesDiscarded() {
        let name = "AppVolumeTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        AppVolumeStore(defaults: defaults).save(["a": 0.4, "b": 0, "full": 1, "invalid": -1])
        XCTAssertEqual(AppVolumeStore(defaults: defaults).load(), ["a": 0.4, "b": 0])
    }
}

@MainActor
final class AppVolumeRouteTests: XCTestCase {
    func testAppearingDisappearingAppFreesSlotAndUsesRouteSeamWhileOtherAudioContinues() {
        let store = EqumaczerStore(startAutomation: false)
        store.channelController.stop()
        let coordinator = store.routingCoordinator
        let channel = ChannelTapAssignment(channel: .calls, objectIDs: [22])
        let app = ChannelTapAssignment(channel: .music, objectIDs: [11], bundleID: "a")
        coordinator.updateChannelTapAssignments([channel])
        let generation = coordinator.routeGeneration
        for i in 0..<100 {
            let assignments = i % 2 == 0 ? [channel, app] : [channel]
            coordinator.updateChannelTapAssignments(assignments)
            let mixer = ChannelMixer(maxFrameCount: 64, appAssignments: assignments)
            mixer.activate(assignments: assignments)
            XCTAssertEqual(mixer.appSlot(for: "a") == nil, i % 2 != 0)
            let signal = [Float](repeating: 0.2, count: 64)
            signal.withUnsafeBufferPointer { signal in
                mixer.slot(for: .calls).write(left: signal.baseAddress!, right: signal.baseAddress!, frameCount: 64)
            }
            mixer.process(frameCount: 64)
            XCTAssertEqual(mixer.output(0)[63], 0.2)
        }
        XCTAssertEqual(coordinator.routeGeneration, generation + 100)
        XCTAssertEqual(coordinator.channelTapAssignments, [channel])
    }
    func testTouchingVolumeSwitchesDriverPreferenceAndPersistsByBundleID() {
        let name = "AppVolumeRouteTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let persistence = AppVolumeStore(defaults: defaults)
        let store = EqumaczerStore(startAutomation: false, appVolumeStore: persistence)
        store.channelController.stop()
        store.captureMode = .sharedMemory
        store.manualModeEnabled = true
        store.updateAppVolume(bundleID: "test.app", volume: 0.4)
        XCTAssertFalse(store.manualModeEnabled)
        XCTAssertEqual(store.captureMode, .processTap)
        XCTAssertEqual(persistence.load()["test.app"], 0.4)
        let restored = EqumaczerStore(startAutomation: false, appVolumeStore: persistence)
        restored.channelController.stop()
        XCTAssertEqual(restored.appVolume(for: "test.app"), 0.4)
        store.updateAppVolume(bundleID: "test.app", volume: 1)
        XCTAssertNil(persistence.load()["test.app"])
    }
}
