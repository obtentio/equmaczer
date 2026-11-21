import XCTest
import Atomics
@testable import equmaczer

final class DuckMixerTests: XCTestCase {
    private let music = ChannelTapAssignment(channel: .music, objectIDs: [11], bundleID: "test.music")
    private let call = ChannelTapAssignment(channel: .calls, objectIDs: [22], bundleID: "test.call")

    private func feed(_ slot: ChannelMixerSlot, _ value: Float, frames: Int = 64) {
        let l = [Float](repeating: value, count: frames)
        l.withUnsafeBufferPointer { slot.write(left: $0.baseAddress!, right: $0.baseAddress!, frameCount: frames) }
    }

    private func run(_ mixer: ChannelMixer, callbacks: Int, music: Float = 1, call: Float = 1) {
        for _ in 0..<callbacks {
            if let slot = mixer.appSlot(for: "test.music") { feed(slot, music) }
            if let slot = mixer.appSlot(for: "test.call") { feed(slot, call) }
            mixer.process(frameCount: 64)
        }
    }

    private var settled: Int { ChannelMixer.duckRampFrames / 64 + 4 }

    func testDuckedMusicIsFifteenPercentAndCallUnchanged() {
        let mixer = ChannelMixer(maxFrameCount: 64, appAssignments: [music, call])
        mixer.activate(assignments: [music])
        mixer.setDucked(true)
        run(mixer, callbacks: settled)
        XCTAssertEqual(mixer.output(0)[63], 0.15, accuracy: 1e-5)

        let both = ChannelMixer(maxFrameCount: 64, appAssignments: [music, call])
        both.activate(assignments: [call])
        both.setDucked(true)
        run(both, callbacks: settled, call: 0.7)
        XCTAssertEqual(both.output(0)[63], 0.7, accuracy: 1e-6)
    }

    func testAppVolumeMultipliesWithDuck() {
        let mixer = ChannelMixer(maxFrameCount: 64, appAssignments: [music])
        mixer.activate(assignments: [music])
        mixer.appSlot(for: "test.music")!.volumeBits.store(Float(0.4).bitPattern, ordering: .relaxed)
        mixer.setDucked(true)
        run(mixer, callbacks: settled)
        XCTAssertEqual(mixer.output(0)[63], 0.06, accuracy: 1e-5)
        // The user moving the volume during a duck keeps the duck.
        mixer.appSlot(for: "test.music")!.volumeBits.store(Float(0.8).bitPattern, ordering: .relaxed)
        run(mixer, callbacks: 8)
        XCTAssertEqual(mixer.output(0)[63], 0.12, accuracy: 1e-5)
    }

    func testRampStepsAreBoundedDownAndUp() {
        let mixer = ChannelMixer(maxFrameCount: 64, appAssignments: [music])
        mixer.activate(assignments: [music])
        var previous: Float = 1
        for ducked in [true, false] {
            mixer.setDucked(ducked)
            for _ in 0..<settled {
                run(mixer, callbacks: 1)
                for frame in 0..<64 {
                    let value = mixer.output(0)[frame]
                    XCTAssertLessThanOrEqual(abs(value - previous), ChannelMixer.duckRampStep + 1e-7)
                    previous = value
                }
            }
            XCTAssertEqual(previous, ducked ? 0.15 : 1, accuracy: 1e-5)
        }
    }

    func testRampIsAboutThreeHundredMilliseconds() {
        let seconds = Double(ChannelMixer.duckRampFrames) / 48_000
        XCTAssertEqual(seconds, 0.3, accuracy: 0.001)
    }

    func testNoAllocationWhileDuckedTenThousandProcesses() {
        let mixer = ChannelMixer(maxFrameCount: 64, appAssignments: [music, call])
        mixer.activate(assignments: [music, call])
        mixer.setDucked(true)
        let left = mixer.output(0), right = mixer.output(1)
        let slot = mixer.appSlot(for: "test.music")!
        let slotLeft = slot.left, slotRight = slot.right
        for _ in 0..<10_000 {
            feed(slot, 0.1)
            mixer.process(frameCount: 64)
            XCTAssertEqual(mixer.output(0), left)
            XCTAssertEqual(mixer.output(1), right)
            XCTAssertEqual(slot.left, slotLeft)
            XCTAssertEqual(slot.right, slotRight)
        }
    }
}

final class CallDuckPolicyTests: XCTestCase {
    func testPolicyChoosesMethod() {
        XCTAssertEqual(CallDuckPolicy.action(mode: .lower, canDuck: true), .duck)
        XCTAssertEqual(CallDuckPolicy.action(mode: .lower, canDuck: false), .pause)
        XCTAssertEqual(CallDuckPolicy.action(mode: .pause, canDuck: true), .pause)
        XCTAssertNil(CallDuckPolicy.action(mode: .nothing, canDuck: true))
    }

    func testLegacyAndUnknownValuesMigrate() throws {
        func load(_ json: String) throws -> ChannelState {
            try JSONDecoder().decode(ChannelState.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try load(#"{"autoPauseEnabled":true}"#).duringCalls, .pause)
        XCTAssertEqual(try load(#"{"autoPauseEnabled":false}"#).duringCalls, .nothing)
        XCTAssertEqual(try load("{}").duringCalls, .lower)
        XCTAssertEqual(try load(#"{"duringCalls":"shout"}"#).duringCalls, .lower)
        XCTAssertEqual(try load(#"{"duringCalls":"nothing","autoPauseEnabled":true}"#).duringCalls, .nothing)
    }

    func testMigrationThroughStorage() {
        let defaults = UserDefaults(suiteName: "test.duck.\(UUID())")!
        defaults.set(Data(#"{"autoPauseEnabled":true}"#.utf8), forKey: "equaliser.channels.v1")
        XCTAssertEqual(ChannelStore(defaults: defaults).load().duringCalls, .pause)
        XCTAssertEqual(ChannelStore(defaults: UserDefaults(suiteName: "test.duck.\(UUID())")!).load().duringCalls, .lower)
    }

    func testRemoteSubLine() {
        XCTAssertEqual(RemotePresentation.subtitle(state: .on, paused: false, ducked: true, preset: "Flat", output: "USB"), "Music lowered for a call")
        XCTAssertEqual(RemotePresentation.subtitle(state: .on, paused: true, preset: "Flat", output: "USB"), "Music paused for a call")
        XCTAssertEqual(RemotePresentation.subtitle(state: .on, paused: false, preset: "Flat", output: "USB"), "Flat · USB")
    }
}

@MainActor
final class DuckStateTests: XCTestCase {
    private func store() -> EqumaczerStore {
        let storage = UserDefaults(suiteName: "equmaczer.duck-tests.\(UUID())")!
        return EqumaczerStore(persistence: AppStatePersistence(storage: storage),
            channelStore: ChannelStore(defaults: storage), startAutomation: false)
    }

    private func drive(_ controller: AutoPauseController, ticks: Int = 3) {
        var time = Date(timeIntervalSince1970: 1_000)
        controller.now = { time }
        controller.stageChanged(true)
        for _ in 0..<ticks { controller.tick(); time += 1.5 }
    }

    func testDriverRouteWithLowerPausesWithoutRouteSwitchOrGeneration() {
        let store = store()
        XCTAssertEqual(store.channelController.state.duringCalls, .lower)
        XCTAssertFalse(store.channelController.canDuck)
        let generation = store.routingCoordinator.routeGeneration
        let captureMode = store.routingCoordinator.captureMode
        var duckCalls: [Bool] = []
        let controller = store.autoPauseController
        controller.pauseTargets = []
        controller.duckApplier = { duckCalls.append($0) }
        drive(controller)
        XCTAssertEqual(controller.holding, .pause)
        XCTAssertFalse(controller.isDucking)
        XCTAssertTrue(duckCalls.isEmpty)
        XCTAssertEqual(store.routingCoordinator.routeGeneration, generation)
        XCTAssertEqual(store.routingCoordinator.captureMode, captureMode)
    }

    func testDuckChangeDoesNotBumpGenerationAndNothingMidCallRestores() {
        let store = store()
        let generation = store.routingCoordinator.routeGeneration
        let controller = store.autoPauseController
        controller.pauseTargets = []
        var duckCalls: [Bool] = []
        controller.canDuckProvider = { true }
        controller.duckApplier = { duckCalls.append($0); store.channelController.setDucked($0) }
        drive(controller)
        XCTAssertEqual(controller.holding, .duck)
        XCTAssertTrue(controller.isDucking)
        XCTAssertEqual(duckCalls, [true])
        store.channelController.setDuringCalls(.nothing)
        controller.tick()
        XCTAssertNil(controller.holding)
        XCTAssertFalse(controller.isDucking)
        XCTAssertEqual(duckCalls, [true, false])
        XCTAssertEqual(store.routingCoordinator.routeGeneration, generation)
    }
}
