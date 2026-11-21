// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// C5: the ritual's gating and ordering — pre-flight facts block
/// or pass, shelves arrive in scope order, passes count honestly.
final class HearingRitualTests: XCTestCase {
    func testPreflightBlocksOnEachMissingFact() {
        XCTAssertFalse(RitualPreflight.evaluate(routingActive: false, inputRMSDB: -20, layerEnabled: true).canProceed)
        XCTAssertFalse(RitualPreflight.evaluate(routingActive: true, inputRMSDB: -80, layerEnabled: true).canProceed)
        XCTAssertFalse(RitualPreflight.evaluate(routingActive: true, inputRMSDB: -20, layerEnabled: false).canProceed)
        XCTAssertTrue(RitualPreflight.evaluate(routingActive: true, inputRMSDB: -20, layerEnabled: true).canProceed)
    }

    func testSignalRequiresRouting() {
        let evaluation = RitualPreflight.evaluate(routingActive: false, inputRMSDB: 0, layerEnabled: true)
        XCTAssertFalse(evaluation.signalArriving, "a hot reading with no route is not signal")
    }

    func testShelfOrderFollowsScope() {
        var ritual = HearingRitual()
        ritual.ears = .together
        XCTAssertEqual(ritual.shelfOrder, [.bothLow, .bothHigh])
        ritual.ears = .separately
        XCTAssertEqual(ritual.shelfOrder, [.leftLow, .leftHigh, .rightLow, .rightHigh])
    }

    func testQuickFinishesAfterOnePass() {
        var ritual = HearingRitual()
        ritual.ears = .together
        ritual.passes = 1
        ritual.goTo(.tune)
        XCTAssertEqual(ritual.currentShelf, .bothLow)
        ritual.confirmShelf()
        XCTAssertEqual(ritual.currentShelf, .bothHigh)
        ritual.confirmShelf()
        XCTAssertEqual(ritual.step, .done)
        XCTAssertNil(ritual.currentShelf)
    }

    func testFullRunsTwoPasses() {
        var ritual = HearingRitual()
        ritual.ears = .together
        ritual.passes = 2
        ritual.goTo(.tune)
        ritual.confirmShelf()
        ritual.confirmShelf()
        XCTAssertEqual(ritual.step, .tune, "pass 2 begins instead of finishing")
        XCTAssertEqual(ritual.pass, 2)
        XCTAssertEqual(ritual.currentShelf, .bothLow)
        ritual.confirmShelf()
        ritual.confirmShelf()
        XCTAssertEqual(ritual.step, .done)
    }

    func testStepsAreJumpable() {
        var ritual = HearingRitual()
        ritual.goTo(.tune)
        XCTAssertEqual(ritual.step, .tune)
        ritual.goTo(.preflight)
        XCTAssertEqual(ritual.step, .preflight)
        ritual.goTo(.done)
        XCTAssertEqual(ritual.step, .done)
    }
}
