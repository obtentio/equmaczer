// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// C6: the approximation shapes are sane as classes — the phone
/// takes the lows away hardest, the car is the only target that
/// adds bass, and every target is a small, readable set of bands.
final class TranslationCheckTests: XCTestCase {
    private func lowShelfGain(_ target: TranslationCheck) -> Float {
        target.bands.first { $0.filterType == .lowShelf }!.gain
    }

    func testEveryTargetIsThreeBands() {
        for target in TranslationCheck.allCases {
            XCTAssertEqual(target.bands.count, 3, "\(target) should stay a broad shape, not a curve")
            XCTAssertFalse(target.account.isEmpty)
        }
    }

    func testPhoneCutsLowsHardest() {
        XCTAssertLessThan(lowShelfGain(.phone), lowShelfGain(.laptop))
        XCTAssertLessThan(lowShelfGain(.laptop), 0)
    }

    func testCarIsTheOnlyBassBoost() {
        XCTAssertGreaterThan(lowShelfGain(.car), 0)
        XCTAssertLessThan(lowShelfGain(.phone), 0)
        XCTAssertLessThan(lowShelfGain(.laptop), 0)
    }

    func testAllTargetsSoftenTheTop() {
        for target in TranslationCheck.allCases {
            let top = target.bands.first { $0.filterType == .highShelf }
            XCTAssertNotNil(top)
            XCTAssertLessThan(top!.gain, 0, "\(target) should not add top end")
        }
    }
}
