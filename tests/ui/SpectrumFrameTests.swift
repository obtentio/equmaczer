import XCTest
@testable import equmaczer

final class SpectrumFrameTests: XCTestCase {
    func testSignatureMatchesEveryRenderedCell() {
        for step in 0...20000 {
            let height = Double(step) / 100
            let signature = SpectrumFrame.signature(height: height)
            guard height > 1 else {
                XCTAssertEqual(signature, [])
                continue
            }
            let rows = Int(ceil(height / 4))
            for row in 0..<rows {
                let occupancy = min(1, (height - Double(row) * 4) / 4)
                let crest = row == rows - 1
                XCTAssertEqual(crest ? signature[1] : 4, QLFLattice.litCount(occupancy: occupancy))
                if !crest {
                    XCTAssertEqual(row < signature[2], (Double(row) * 4 + 2) / height < 0.6)
                }
            }
        }
    }

    func testInvisibleChangesAndSilenceDoNotInvalidateFrame() {
        let size = CGSize(width: 100, height: 100)
        XCTAssertEqual(SpectrumFrame(bands: [-40, -40], size: size),
                       SpectrumFrame(bands: [-40.00001, -40.00001], size: size))
        XCTAssertEqual(SpectrumFrame(bands: [], size: size),
                       SpectrumFrame(bands: [-100, -100], size: size))
        XCTAssertNotEqual(SpectrumFrame(bands: [-40, -40], size: size),
                          SpectrumFrame(bands: [-20, -20], size: size))
    }
}
