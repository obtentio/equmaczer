// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// The unified cascade preamp: the correction layer absorbs only
/// the marginal headroom the true cascade peak needs above the
/// manual layer's preamp, instead of the two layers' peaks summing.
final class CascadePreampTests: XCTestCase {

    private func vector(peaks: [Int: Float]) -> [Float] {
        var values = [Float](repeating: 0, count: 512)
        for (index, db) in peaks { values[index] = db }
        return values
    }

    private func layer(
        peaks: [Int: Float],
        recommended: Double,
        sampleRate: Double = 48000
    ) -> EQConfiguration.CascadeLayerData {
        EQConfiguration.CascadeLayerData(
            channels: [EQConfiguration.CascadeLayerData.ChannelData(
                coefficients: [],
                bypassFlags: [],
                activeBandCount: 0,
                candidateFrequencies: [],
                magnitudeDB: vector(peaks: peaks)
            )],
            recommendedPreampDB: recommended,
            sampleRate: sampleRate
        )
    }

    @MainActor
    func testDisjointPeaksDoNotSum() {
        let config = EQConfiguration()
        config.updateManualCascade(layer(peaks: [10: 4], recommended: -4.2))
        config.updateCorrectionCascade(layer(peaks: [300: 6], recommended: -6.2), profilePreampDB: 0)

        XCTAssertEqual(config.autoPreampDB, -4.2, accuracy: 0.001)
        // True cascade peak is +6, not +10: total cut is −6.2.
        XCTAssertEqual(config.correctionPreampDB, -2.0, accuracy: 0.001)
        XCTAssertEqual(config.effectiveInputGainDB, -6.2, accuracy: 0.001)
    }

    @MainActor
    func testOpposingBoostRecoversTheOverlap() {
        let config = EQConfiguration()
        // Manual cuts 105 Hz by 4 and peaks +2 elsewhere; correction
        // boosts the same 105 Hz point by 8. Cascade peak there: +4.
        config.updateManualCascade(layer(peaks: [40: -4, 200: 2], recommended: -2.2))
        config.updateCorrectionCascade(layer(peaks: [40: 8], recommended: -8.2), profilePreampDB: 0)

        XCTAssertEqual(config.correctionPreampDB, -2.0, accuracy: 0.001)
        XCTAssertEqual(config.effectiveInputGainDB, -4.2, accuracy: 0.001)
    }

    @MainActor
    func testCutSideKeepsTheManualPreampByDesign() {
        let config = EQConfiguration()
        // Correction cancels the manual peak exactly; the displayed
        // manual preamp is never undercut, so the total stays at it.
        config.updateManualCascade(layer(peaks: [100: 6], recommended: -6.2))
        config.updateCorrectionCascade(layer(peaks: [100: -6], recommended: 0), profilePreampDB: 0)

        XCTAssertEqual(config.correctionPreampDB, 0, accuracy: 0.001)
        XCTAssertEqual(config.effectiveInputGainDB, -6.2, accuracy: 0.001)
    }

    @MainActor
    func testProfileDeclaredPreampRemainsAFloor() {
        let config = EQConfiguration()
        config.updateManualCascade(layer(peaks: [10: 4], recommended: -4.2))
        config.updateCorrectionCascade(layer(peaks: [300: 6], recommended: -6.2), profilePreampDB: -9)

        XCTAssertEqual(config.correctionPreampDB, -9, accuracy: 0.001)
    }

    @MainActor
    func testAutoPreampOffKeepsTheStandaloneCorrectionPreamp() {
        let config = EQConfiguration()
        config.updateManualCascade(layer(peaks: [10: 4], recommended: -4.2))
        config.updateCorrectionCascade(layer(peaks: [300: 6], recommended: -6.2), profilePreampDB: 0)
        config.autoPreampEnabled = false

        XCTAssertEqual(config.correctionPreampDB, -6.2, accuracy: 0.001)
    }

    @MainActor
    func testSampleRateMismatchFallsBackToStandalone() {
        let config = EQConfiguration()
        config.updateManualCascade(layer(peaks: [10: 4], recommended: -4.2))
        config.updateCorrectionCascade(layer(peaks: [300: 6], recommended: -6.2, sampleRate: 44100), profilePreampDB: 0)

        XCTAssertEqual(config.correctionPreampDB, -6.2, accuracy: 0.001)
    }
}

@MainActor
final class ManualLayerSwitchTests: XCTestCase {
    func testDisablingManualLayerReleasesHeadroomWithoutErasingBands() {
        let config = EQConfiguration(initialBandCount: 10)
        let stager = EQCoefficientStager(eqConfiguration: config)
        config.updateBandGain(index: 0, gain: 8)
        stager.reapplyConfiguration()
        XCTAssertLessThan(config.autoPreampDB, -7)
        config.userEQEnabled = false
        stager.reapplyConfiguration()
        XCTAssertEqual(config.autoPreampDB, 0)
        XCTAssertEqual(config.bands[0].gain, 8)
        XCTAssertTrue(config.leftState.userEQ.bypass)
        XCTAssertTrue(config.rightState.userEQ.bypass)
        config.userEQEnabled = true
        stager.reapplyConfiguration()
        XCTAssertLessThan(config.autoPreampDB, -7)
    }
}
