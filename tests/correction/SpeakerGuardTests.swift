// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// D6: the speaker guard is cuts-only, carries its honesty in
/// its source details, and its composite shape (measured with
/// the analog evaluator, the B6 pattern) takes the deep lows
/// away while leaving the midrange alone.
final class SpeakerGuardTests: XCTestCase {
    private func compositeDB(at frequency: Double) -> Double {
        let result = SpeakerGuard.importResult(deviceUID: "built-in", deviceName: "Built-in Output")
        return result.profile.bands.reduce(0.0) { sum, band in
            sum + SVFMath.analogMagnitudeDB(
                type: band.filterType,
                frequency: Double(band.frequency),
                q: Double(band.q),
                gain: Double(band.gain),
                at: frequency
            )
        }
    }

    func testGuardIsCutsOnly() {
        let result = SpeakerGuard.importResult(deviceUID: "built-in", deviceName: "Built-in Output")
        XCTAssertEqual(result.profile.preampDB, 0)
        XCTAssertTrue(result.profile.bands.allSatisfy { $0.gain <= 0 }, "a guard that boosts contradicts itself")
        XCTAssertTrue(result.profile.bands.contains { $0.filterType == .highPass })
        XCTAssertEqual(result.profile.sourceName, SpeakerGuard.sourceName)
        XCTAssertTrue(result.profile.sourceDetails?.contains("not a measurement") ?? false)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testGuardShapeRemovesDeepLowsAndLeavesMids() {
        XCTAssertLessThan(compositeDB(at: 40), -8, "deep lows a small driver cannot reproduce should be well down")
        XCTAssertLessThan(compositeDB(at: 200), -1, "the boom region is tamed")
        XCTAssertEqual(compositeDB(at: 1_000), 0, accuracy: 0.5, "the midrange is not the problem and is left alone")
    }
}
