import XCTest
@testable import equmaczer

final class REWExporterTests: XCTestCase {
    func testEveryFilterTypeAndBypassRoundTripsThroughREWText() throws {
        let types: [FilterType] = [.parametric, .lowShelf, .highShelf, .lowPass, .highPass, .bandPass, .notch]
        let bands = types.enumerated().map { index, type in
            PresetBand(frequency: Float(100 + index * 100), q: 1.5, gain: -3, filterType: type, bypass: index % 2 == 0)
        }
        let imported = try REWImporter.parseFilterText(REWExporter.export(bands: bands), filename: "roundtrip.txt")
        XCTAssertEqual(imported.bands.count, bands.count)
        XCTAssertTrue(imported.warnings.isEmpty)
        for (actual, expected) in zip(imported.bands, bands) {
            XCTAssertEqual(actual.filterType, expected.filterType)
            XCTAssertEqual(actual.frequency, expected.frequency)
            XCTAssertEqual(actual.q, expected.q)
            XCTAssertEqual(actual.gain, expected.gain)
            XCTAssertEqual(actual.bypass, expected.bypass)
        }
    }
}
