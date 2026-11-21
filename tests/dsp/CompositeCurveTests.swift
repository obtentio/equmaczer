// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// The composite-curve evaluator behind the Zone D curve canvas: a flat
/// EQ reads 0 dB everywhere; a peaking band reads its gain at its centre.
@MainActor
final class CompositeCurveTests: XCTestCase {

    private func curveDB(
        config: EQConfiguration,
        count: Int,
        at frequency: Double
    ) -> Double {
        let stager = EQCoefficientStager(eqConfiguration: config)
        let bands = config.bands
        return HeadroomAnalyzer.compositeGainDB(
            svfCoefficients: stager.designedCoefficients(for: bands, count: count),
            bypassFlags: bands.map(\.bypass),
            activeBandCount: count,
            sampleRate: stager.sampleRate,
            at: frequency
        )
    }

    /// A configuration the way the app actually runs it: the active
    /// bands re-spread across the spectrum for their count.
    private func makeConfig() -> EQConfiguration {
        let config = EQConfiguration(initialBandCount: 10)
        config.resetBandsWithFrequencySpread()
        return config
    }

    func testFlatEQReadsZeroEverywhere() {
        let config = makeConfig()
        for frequency in [50.0, 200.0, 1000.0, 5000.0, 12000.0] {
            XCTAssertEqual(curveDB(config: config, count: 10, at: frequency), 0, accuracy: 0.05,
                           "flat EQ must read 0 dB at \(frequency) Hz")
        }
    }

    /// Index of the active band nearest 1 kHz (a fresh 10-band
    /// configuration spreads ISO octaves, so this is the 1 kHz band).
    private func bandNear1kHz(_ config: EQConfiguration, count: Int) -> Int {
        config.bands.prefix(count).enumerated().min {
            abs(log2(Double($0.element.frequency) / 1000)) < abs(log2(Double($1.element.frequency) / 1000))
        }!.offset
    }

    func testPeakingBandReadsItsGainAtCentre() {
        let config = makeConfig()
        let index = bandNear1kHz(config, count: 10)
        let centre = Double(config.bands[index].frequency)
        config.updateBandGain(index: index, gain: 6)
        XCTAssertEqual(curveDB(config: config, count: 10, at: centre), 6, accuracy: 0.3)
        // Far below the band, the curve returns to ~0 dB.
        XCTAssertEqual(curveDB(config: config, count: 10, at: 40), 0, accuracy: 0.5)
    }

    func testBypassedBandContributesNothing() {
        let config = makeConfig()
        let index = bandNear1kHz(config, count: 10)
        let centre = Double(config.bands[index].frequency)
        config.updateBandGain(index: index, gain: 9)
        config.updateBandBypass(index: index, bypass: true)
        XCTAssertEqual(curveDB(config: config, count: 10, at: centre), 0, accuracy: 0.05)
    }
}
