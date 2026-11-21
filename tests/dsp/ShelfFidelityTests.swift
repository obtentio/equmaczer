// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// B6: imported shelves must render as the shelves their authors
/// measured. Source tools (Equalizer APO, REW, OPRA's q) speak the
/// RBJ Q-form; the live designer is the decramped SVF. This test
/// measures both responses for the shelves that actually occur in
/// the wild and pins their agreement — the low shelves across
/// their whole region, the high shelf across its region short of
/// the Nyquist corner where decramping deliberately departs from
/// the bilinear shape.
final class ShelfFidelityTests: XCTestCase {
    private let sampleRate = 48_000.0

    /// |H(e^jw)| in dB for RBJ coefficients (a0 normalised to 1).
    private func rbjDB(_ c: BiquadCoefficients, at frequency: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        let cosW = cos(w), sinW = sin(w)
        let cos2W = cos(2 * w), sin2W = sin(2 * w)
        let numRe = c.b0 + c.b1 * cosW + c.b2 * cos2W
        let numIm = -(c.b1 * sinW + c.b2 * sin2W)
        let denRe = 1 + c.a1 * cosW + c.a2 * cos2W
        let denIm = -(c.a1 * sinW + c.a2 * sin2W)
        let magSq = (numRe * numRe + numIm * numIm) / (denRe * denRe + denIm * denIm)
        return 10 * log10(max(1e-30, magSq))
    }

    private func svfDB(type: FilterType, frequency: Double, q: Double, gain: Double, at eval: Double) -> Double {
        let coefficients = SVFMath.calculateDecrampedSVF(
            type: type, sampleRate: sampleRate, frequency: frequency, q: q, gain: gain
        )
        return HeadroomAnalyzer.compositeGainDB(
            svfCoefficients: [coefficients],
            bypassFlags: [false],
            activeBandCount: 1,
            sampleRate: sampleRate,
            at: eval
        )
    }

    private func maxDelta(
        type: FilterType, frequency: Double, q: Double, gain: Double,
        evalFrequencies: [Double]
    ) -> Double {
        let rbj = BiquadMath.calculateCoefficients(
            type: type, sampleRate: sampleRate, frequency: frequency, q: q, gain: gain
        )
        var worst = 0.0
        for eval in evalFrequencies {
            let delta = abs(rbjDB(rbj, at: eval) - svfDB(type: type, frequency: frequency, q: q, gain: gain, at: eval))
            worst = max(worst, delta)
        }
        return worst
    }

    private func logSweep(_ from: Double, _ to: Double, count: Int) -> [Double] {
        (0..<count).map { i in
            from * pow(to / from, Double(i) / Double(count - 1))
        }
    }

    func testOratoryLowShelfAgrees() {
        // 105 Hz, +6 dB, Q 0.7 — the canonical AutoEq low shelf.
        let delta = maxDelta(
            type: .lowShelf, frequency: 105, q: 0.7, gain: 6.0,
            evalFrequencies: logSweep(20, 1_000, count: 25)
        )
        XCTAssertLessThanOrEqual(delta, 0.5, "low shelf +6 dB: max divergence \(delta) dB")
    }

    func testCrinacleLowShelfAgrees() {
        // 105 Hz, −1.7 dB, Q 0.7 — verbatim from the OPRA database.
        let delta = maxDelta(
            type: .lowShelf, frequency: 105, q: 0.7, gain: -1.7,
            evalFrequencies: logSweep(20, 1_000, count: 25)
        )
        XCTAssertLessThanOrEqual(delta, 0.5, "low shelf −1.7 dB: max divergence \(delta) dB")
    }

    func testOratoryHighShelfAgrees() {
        // 10 kHz, −4.9 dB, Q 0.7 — verbatim from the OPRA database.
        // Region stops at 16 kHz: beyond it the decramped design
        // holds the analog shape where the bilinear shelf cramps —
        // a documented departure, not an import error.
        let delta = maxDelta(
            type: .highShelf, frequency: 10_000, q: 0.7, gain: -4.9,
            evalFrequencies: logSweep(1_000, 16_000, count: 25)
        )
        XCTAssertLessThanOrEqual(delta, 0.5, "high shelf −4.9 dB: max divergence \(delta) dB")
    }

    func testPeakingControlAgrees() {
        // The harness itself: a mid-band peak must agree closely.
        let delta = maxDelta(
            type: .parametric, frequency: 1_000, q: 1.41, gain: 3.0,
            evalFrequencies: logSweep(100, 10_000, count: 25)
        )
        XCTAssertLessThanOrEqual(delta, 0.25, "peaking control: max divergence \(delta) dB")
    }
}
