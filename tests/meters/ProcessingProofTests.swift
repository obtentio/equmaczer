// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// B2: the proof verdict matrix, including the two honesty edges —
/// bypass is a state fact, and a zero loudness delta with signal
/// present never reads as "not processing".
final class ProcessingProofTests: XCTestCase {
    func testNotRoutingWinsOverEverything() {
        let verdict = ProcessingProof.verdict(
            routingActive: false, bypassed: true,
            inputRMSDB: -12, outputRMSDB: -12, effectLU: 2.0
        )
        XCTAssertEqual(verdict, .notRouting)
    }

    func testBypassedIsAStateFact() {
        let verdict = ProcessingProof.verdict(
            routingActive: true, bypassed: true,
            inputRMSDB: -12, outputRMSDB: -12, effectLU: 2.0
        )
        XCTAssertEqual(verdict, .bypassed)
    }

    func testSilentInputWaitsForSignal() {
        let verdict = ProcessingProof.verdict(
            routingActive: true, bypassed: false,
            inputRMSDB: -90, outputRMSDB: -90, effectLU: nil
        )
        XCTAssertEqual(verdict, .waitingForSignal)
        XCTAssertTrue(verdict.line.contains("isn't reaching equmaczer"))
    }

    func testSignalWithoutDeltaYetIsMeasuring() {
        let verdict = ProcessingProof.verdict(
            routingActive: true, bypassed: false,
            inputRMSDB: -12, outputRMSDB: -13, effectLU: nil
        )
        XCTAssertEqual(verdict, .measuringEffect(inputDB: -12, outputDB: -13))
    }

    func testRealDeltaIsProcessing() {
        let verdict = ProcessingProof.verdict(
            routingActive: true, bypassed: false,
            inputRMSDB: -12, outputRMSDB: -14, effectLU: -1.8
        )
        XCTAssertEqual(verdict, .processing(inputDB: -12, outputDB: -14, effectLU: -1.8))
        XCTAssertTrue(verdict.line.contains("-1.8 LU"))
    }

    // MARK: - B7: bypass honesty

    func testComparingFlatBeatsTheDeltaVerdicts() {
        // The EQ is off and the delta is a held value — the
        // verdict must describe the compare, not claim processing.
        let verdict = ProcessingProof.verdict(
            routingActive: true, bypassed: false,
            comparingFlat: true, matchEnabled: true,
            inputRMSDB: -12, outputRMSDB: -12, effectLU: -1.8
        )
        XCTAssertEqual(verdict, .comparingFlat(matchDB: 1.8))
        XCTAssertTrue(verdict.line.contains("EQ off"))
    }

    func testComparingFlatWithoutMatch() {
        let verdict = ProcessingProof.verdict(
            routingActive: true, bypassed: false,
            comparingFlat: true, matchEnabled: false,
            inputRMSDB: -12, outputRMSDB: -12, effectLU: -1.8
        )
        XCTAssertEqual(verdict, .comparingFlatUnmatched)
    }

    func testComparingFlatBeforeAnyMeasurement() {
        let verdict = ProcessingProof.verdict(
            routingActive: true, bypassed: false,
            comparingFlat: true, matchEnabled: true,
            inputRMSDB: -12, outputRMSDB: -12, effectLU: nil
        )
        XCTAssertEqual(verdict, .comparingFlatUnmeasured)
    }

    func testBypassedLineNamesTheVolumeException() {
        let verdict = ProcessingProof.verdict(
            routingActive: true, bypassed: true,
            inputRMSDB: -12, outputRMSDB: -12, effectLU: nil
        )
        XCTAssertTrue(verdict.line.contains("Volume still applies"))
    }

    func testZeroDeltaNeverClaimsNotProcessing() {
        let verdict = ProcessingProof.verdict(
            routingActive: true, bypassed: false,
            inputRMSDB: -12, outputRMSDB: -12, effectLU: 0.02
        )
        XCTAssertEqual(verdict, .flowingNoMeasuredChange(inputDB: -12, outputDB: -12))
        XCTAssertTrue(verdict.line.contains("loudness-neutral"))
        XCTAssertFalse(verdict.line.lowercased().contains("not processing"))
    }
}
