// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// C1: the sketch fitter, tested against target curves generated
/// from known bands — recovery is measured, not eyeballed.
final class SketchFitterTests: XCTestCase {
    /// Samples the composite analog response of `bands` on a dense
    /// log sweep across [from, to] — a synthetic "stroke".
    private func stroke(
        from bands: [EQBandConfiguration],
        from: Double = 20, to: Double = 20_000, count: Int = 200
    ) -> [(frequency: Double, db: Double)] {
        (0..<count).map { i in
            let frequency = from * pow(to / from, Double(i) / Double(count - 1))
            let db = bands.reduce(0.0) { sum, band in
                sum + SVFMath.analogMagnitudeDB(
                    type: band.filterType,
                    frequency: Double(band.frequency),
                    q: Double(band.q),
                    gain: Double(band.gain),
                    at: frequency
                )
            }
            return (frequency: frequency, db: db)
        }
    }

    private func band(_ type: FilterType, _ frequency: Float, _ q: Float, _ gain: Float) -> EQBandConfiguration {
        EQBandConfiguration(frequency: frequency, q: q, gain: gain, filterType: type, bypass: false)
    }

    func testSinglePeakRecovered() {
        let target = [band(.parametric, 250, 2.0, 4.0)]
        let proposal = SketchFitter.fit(samples: stroke(from: target))
        XCTAssertEqual(proposal.bands.count, 1)
        let fitted = proposal.bands[0]
        XCTAssertEqual(fitted.filterType, .parametric)
        XCTAssertEqual(Double(fitted.frequency), 250, accuracy: 40)
        XCTAssertEqual(Double(fitted.gain), 4.0, accuracy: 0.6)
        XCTAssertLessThan(proposal.maxErrorDB, 0.75)
    }

    func testBassPlateauBecomesAShelfNotPeaks() {
        let target = [band(.lowShelf, 105, 0.7, 5.0)]
        let proposal = SketchFitter.fit(samples: stroke(from: target))
        XCTAssertEqual(proposal.bands.count, 1)
        XCTAssertEqual(proposal.bands[0].filterType, .lowShelf)
        XCTAssertEqual(Double(proposal.bands[0].gain), 5.0, accuracy: 0.5)
    }

    func testShelfPlusPeakYieldsBoth() {
        let target = [band(.lowShelf, 105, 0.7, 4.0), band(.parametric, 3_000, 1.5, -3.0)]
        let proposal = SketchFitter.fit(samples: stroke(from: target))
        XCTAssertEqual(proposal.bands.count, 2)
        XCTAssertEqual(proposal.bands[0].filterType, .lowShelf)
        XCTAssertEqual(proposal.bands[1].filterType, .parametric)
        XCTAssertEqual(Double(proposal.bands[1].frequency), 3_000, accuracy: 500)
        XCTAssertLessThan(proposal.maxErrorDB, 1.0)
    }

    func testFlatStrokeProposesNothing() {
        let samples = stroke(from: [])
        let proposal = SketchFitter.fit(samples: samples)
        XCTAssertTrue(proposal.bands.isEmpty)
        XCTAssertEqual(proposal.maxErrorDB, 0, accuracy: 0.01)
    }

    func testPartialSpanStrokeStaysInItsSpan() {
        // A stroke covering only 100 Hz–1 kHz: no edge shelves,
        // and no band outside the covered span.
        let target = [band(.parametric, 400, 1.5, 3.0)]
        let samples = stroke(from: target, from: 100, to: 1_000)
        let proposal = SketchFitter.fit(samples: samples)
        XCTAssertFalse(proposal.bands.isEmpty)
        for fitted in proposal.bands {
            XCTAssertEqual(fitted.filterType, .parametric)
            XCTAssertGreaterThanOrEqual(Double(fitted.frequency), 90)
            XCTAssertLessThanOrEqual(Double(fitted.frequency), 1_100)
        }
    }

    func testTwoPeaksRecovered() {
        let target = [band(.parametric, 150, 1.5, 3.0), band(.parametric, 6_000, 2.0, -4.0)]
        let proposal = SketchFitter.fit(samples: stroke(from: target))
        XCTAssertEqual(proposal.bands.count, 2)
        XCTAssertEqual(Double(proposal.bands[0].frequency), 150, accuracy: 30)
        XCTAssertEqual(Double(proposal.bands[1].frequency), 6_000, accuracy: 900)
        XCTAssertLessThan(proposal.maxErrorDB, 1.0)
    }
}
