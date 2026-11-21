import XCTest
@testable import equmaczer

final class WindowLayoutTests: XCTestCase {
    func testDescribeFieldShrinksBeforePresetsOverflow() {
        let roomy = PresetRowLayout.fit(chipWidths: [60, 80], width: 550)
        let smaller = PresetRowLayout.fit(chipWidths: [60, 80], width: 440)
        XCTAssertEqual(roomy.visibleCount, 2)
        XCTAssertEqual(smaller.visibleCount, 2)
        XCTAssertLessThan(smaller.describeWidth, roomy.describeWidth)
        XCTAssertGreaterThanOrEqual(smaller.describeWidth, 110)
    }
    func testPresetOverflowReservesSaveAndMinimumField() {
        let result = PresetRowLayout.fit(chipWidths: [80, 100, 100], width: 500)
        XCTAssertEqual(result.visibleCount, 2)
        XCTAssertGreaterThanOrEqual(result.describeWidth, 110)
    }
}
