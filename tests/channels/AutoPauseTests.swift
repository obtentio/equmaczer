// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// A8 auto-pause: the engine's timing on fake time, and the new
/// state field's round-trip.
final class AutoPauseEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testEngageAfterHoldNotBefore() {
        var engine = AutoPauseEngine()
        XCTAssertNil(engine.update(stageActive: true, now: t0))
        XCTAssertNil(engine.update(stageActive: true, now: t0.addingTimeInterval(1.9)))
        XCTAssertEqual(engine.update(stageActive: true, now: t0.addingTimeInterval(2.0)), .pause)
        XCTAssertTrue(engine.engaged)
        // Holding the stage doesn't re-fire.
        XCTAssertNil(engine.update(stageActive: true, now: t0.addingTimeInterval(30)))
    }

    func testBlipUnderEngageDelayDoesNothing() {
        var engine = AutoPauseEngine()
        XCTAssertNil(engine.update(stageActive: true, now: t0))
        XCTAssertNil(engine.update(stageActive: false, now: t0.addingTimeInterval(1)))
        XCTAssertFalse(engine.engaged)
        // A later real stage starts its hold from scratch.
        XCTAssertNil(engine.update(stageActive: true, now: t0.addingTimeInterval(10)))
        XCTAssertNil(engine.update(stageActive: true, now: t0.addingTimeInterval(11.9)))
        XCTAssertEqual(engine.update(stageActive: true, now: t0.addingTimeInterval(12)), .pause)
    }

    func testResumeAfterLongerClearDelay() {
        var engine = AutoPauseEngine()
        _ = engine.update(stageActive: true, now: t0)
        _ = engine.update(stageActive: true, now: t0.addingTimeInterval(2))
        XCTAssertTrue(engine.engaged)

        let clearStart = t0.addingTimeInterval(100)
        XCTAssertNil(engine.update(stageActive: false, now: clearStart))
        XCTAssertNil(engine.update(stageActive: false, now: clearStart.addingTimeInterval(4.9)))
        XCTAssertEqual(engine.update(stageActive: false, now: clearStart.addingTimeInterval(5)), .resume)
        XCTAssertFalse(engine.engaged)
    }

    func testStageReturningDuringClearDelayCancelsResume() {
        var engine = AutoPauseEngine()
        _ = engine.update(stageActive: true, now: t0)
        _ = engine.update(stageActive: true, now: t0.addingTimeInterval(2))

        let clearStart = t0.addingTimeInterval(50)
        XCTAssertNil(engine.update(stageActive: false, now: clearStart))
        // Stage returns at +3 s: the pending resume dies, no action.
        XCTAssertNil(engine.update(stageActive: true, now: clearStart.addingTimeInterval(3)))
        XCTAssertTrue(engine.engaged)
        // And a later clear needs the full delay again.
        let secondClear = clearStart.addingTimeInterval(60)
        XCTAssertNil(engine.update(stageActive: false, now: secondClear))
        XCTAssertNil(engine.update(stageActive: false, now: secondClear.addingTimeInterval(4.9)))
        XCTAssertEqual(engine.update(stageActive: false, now: secondClear.addingTimeInterval(5)), .resume)
    }
}

final class AutoPauseStateTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.autopause.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDuringCallsDefaultsToLowerAndRoundTrips() {
        let store = ChannelStore(defaults: defaults)
        XCTAssertEqual(store.load().duringCalls, .lower)

        var state = ChannelState()
        state.duringCalls = .pause
        store.save(state)
        XCTAssertEqual(store.load().duringCalls, .pause)
    }
}
