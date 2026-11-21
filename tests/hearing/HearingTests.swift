// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// A5 hearing layer: per-ear composition at the shared shelf
/// constants, zero omission, the disabled state composing empty,
/// and the state round-trip.
final class HearingCompositionTests: XCTestCase {
    func testPerEarShelvesAtSharedConstants() {
        var state = HearingState()
        state.enabled = true
        state.leftLowDB = 4
        state.leftHighDB = -2
        state.rightLowDB = 0
        state.rightHighDB = 6

        let left = HearingComposition.leftBands(for: state)
        XCTAssertEqual(left.count, 2)
        XCTAssertEqual(left[0].filterType, .lowShelf)
        XCTAssertEqual(left[0].frequency, CorrectionComposer.lowShelfHz)
        XCTAssertEqual(left[0].q, CorrectionComposer.shelfQ)
        XCTAssertEqual(left[0].gain, 4, accuracy: 0.001)
        XCTAssertEqual(left[1].filterType, .highShelf)
        XCTAssertEqual(left[1].frequency, CorrectionComposer.highShelfHz)
        XCTAssertEqual(left[1].gain, -2, accuracy: 0.001)

        let right = HearingComposition.rightBands(for: state)
        XCTAssertEqual(right.count, 1, "The zero low gain is omitted, not staged as a 0 dB band")
        XCTAssertEqual(right[0].filterType, .highShelf)
        XCTAssertEqual(right[0].gain, 6, accuracy: 0.001)
    }

    func testDisabledComposesEmptyForBothEars() {
        var state = HearingState()
        state.enabled = false
        state.leftLowDB = 8
        state.rightHighDB = 8
        XCTAssertTrue(HearingComposition.leftBands(for: state).isEmpty)
        XCTAssertTrue(HearingComposition.rightBands(for: state).isEmpty)
    }

    func testResetZeroesAllSliders() {
        var state = HearingState()
        state.leftLowDB = 3
        state.leftHighDB = -5
        state.rightLowDB = 12
        state.rightHighDB = 1
        state.reset()
        XCTAssertEqual(state, HearingState())
    }
}

final class HearingStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.hearing.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRoundTrip() {
        let store = HearingStore(defaults: defaults)
        XCTAssertEqual(store.load(), HearingState())

        var state = HearingState()
        state.enabled = true
        state.leftLowDB = 2.5
        state.rightHighDB = -4
        store.save(state)
        XCTAssertEqual(store.load(), state)
    }
}
