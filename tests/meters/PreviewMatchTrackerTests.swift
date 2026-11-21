// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// A1 preview level-matching: the offset is the difference between
/// the saved sound's paired delta (the reference) and the preview's,
/// clamped to the matched bypass's ±12 dB, and the matched preamp
/// may spend the published headroom but never exceed 0 dB.
final class PreviewMatchTrackerTests: XCTestCase {
    func testOffsetIsReferenceMinusCurrent() {
        // Preview runs 5 dB quieter than the saved sound → raise it.
        XCTAssertEqual(
            PreviewMatchTracker.offsetDB(referenceDeltaDB: -2, currentDeltaDB: -7),
            5, accuracy: 0.001
        )
        // Preview runs 5 dB louder → lower it.
        XCTAssertEqual(
            PreviewMatchTracker.offsetDB(referenceDeltaDB: -7, currentDeltaDB: -2),
            -5, accuracy: 0.001
        )
        // Identical deltas need no offset.
        XCTAssertEqual(
            PreviewMatchTracker.offsetDB(referenceDeltaDB: -3, currentDeltaDB: -3),
            0, accuracy: 0.001
        )
    }

    func testOffsetClampsToMatchedBypassRange() {
        XCTAssertEqual(
            PreviewMatchTracker.offsetDB(referenceDeltaDB: 0, currentDeltaDB: -30),
            12, accuracy: 0.001
        )
        XCTAssertEqual(
            PreviewMatchTracker.offsetDB(referenceDeltaDB: -30, currentDeltaDB: 0),
            -12, accuracy: 0.001
        )
    }

    func testMatchedPreampSpendsHeadroomButNeverGoesPositive() {
        // Published −6.4 dB with a +5 dB offset composes at −1.4 dB.
        XCTAssertEqual(
            PreviewMatchTracker.matchedPreampDB(publishedPreampDB: -6.4, offsetDB: 5),
            -1.4, accuracy: 0.001
        )
        // A large offset stops at 0 dB: matching never adds gain
        // past unity against the correction's own headroom.
        XCTAssertEqual(
            PreviewMatchTracker.matchedPreampDB(publishedPreampDB: -2, offsetDB: 12),
            0, accuracy: 0.001
        )
        // A negative offset lowers the preamp further.
        XCTAssertEqual(
            PreviewMatchTracker.matchedPreampDB(publishedPreampDB: -3, offsetDB: -4),
            -7, accuracy: 0.001
        )
    }
}
