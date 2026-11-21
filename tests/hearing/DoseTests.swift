// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// A6 dose maths at its reference points, the stated anchor, and
/// the daily-bucket round-trip.
final class DoseMathTests: XCTestCase {
    func testReferencePoint() {
        // 80 dBA for the full 40 hours spends exactly the budget.
        let fraction = DoseMath.doseFraction(levelDBA: 80, durationSeconds: 40 * 3600)
        XCTAssertEqual(fraction, 1.0, accuracy: 0.0001)
    }

    func testExchangeRate() {
        // +3 dB halves the allowed time; −3 dB doubles it.
        XCTAssertEqual(DoseMath.doseFraction(levelDBA: 83, durationSeconds: 20 * 3600), 1.0, accuracy: 0.0001)
        XCTAssertEqual(DoseMath.doseFraction(levelDBA: 77, durationSeconds: 80 * 3600), 1.0, accuracy: 0.0001)
        XCTAssertEqual(DoseMath.doseFraction(levelDBA: 86, durationSeconds: 10 * 3600), 1.0, accuracy: 0.0001)
    }

    func testAnchorAndVolume() {
        // Full-scale output at full volume is the stated 100 dBA anchor.
        XCTAssertEqual(DoseMath.estimatedLevelDBA(outputRmsDBFS: 0, volumeDB: 0), 100, accuracy: 0.0001)
        // A half volume scalar is −6.02 dB of device volume.
        let halfVolumeDB = 20 * log10(0.5)
        XCTAssertEqual(
            DoseMath.estimatedLevelDBA(outputRmsDBFS: -20, volumeDB: halfVolumeDB),
            100 - 20 - 6.02,
            accuracy: 0.01
        )
        // Silence spends nothing worth counting: an hour at −90 dBFS
        // is a vanishing fraction of the budget.
        let quiet = DoseMath.doseFraction(
            levelDBA: DoseMath.estimatedLevelDBA(outputRmsDBFS: -90, volumeDB: 0),
            durationSeconds: 3600
        )
        XCTAssertLessThan(quiet, 0.0001)
    }

    func testZeroDurationSpendsNothing() {
        XCTAssertEqual(DoseMath.doseFraction(levelDBA: 100, durationSeconds: 0), 0)
    }
}

final class DoseStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.dose.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRoundTripAndPruning() {
        let store = DoseStore(defaults: defaults)
        XCTAssertTrue(store.load().isEmpty)

        let now = Date()
        let todayKey = DoseStore.dayKey(for: now)
        let ancientKey = DoseStore.dayKey(for: now.addingTimeInterval(-30 * 24 * 3600))
        store.save([todayKey: 0.25, ancientKey: 0.9], now: now)

        let loaded = store.load()
        XCTAssertEqual(loaded[todayKey] ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertNil(loaded[ancientKey], "Buckets older than 14 days are pruned on save")
    }
}
