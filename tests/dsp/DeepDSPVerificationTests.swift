// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
// DeepDSPVerificationTests.swift
// Falsifiable verification tests for decramped Float64 TPT SVF, ITU-R BS.1770-4 True-Peak,
// analytical headroom, real-time execution latency, and CoreAudio Process Tap configuration.

import CoreAudio
import XCTest
@testable import equmaczer

final class DeepDSPVerificationTests: XCTestCase {

    // MARK: - 1. Full 5-Pillar Falsifiable Benchmark Suite

    func testAllFiveFalsifiableCriteriaPass() {
        let report = DSPBenchmarkSuite.runAll()
        print("\n" + report.formattedSummary())

        // (a) < 0.05 dB Nyquist cramping error at 18 kHz @ fs = 44.1 kHz (vs > 1.5 dB for RBJ)
        XCTAssertGreaterThan(
            report.legacyError18kHzDB,
            1.50,
            "Legacy RBJ bilinear transform should exhibit > 1.5 dB Nyquist cramping at 18 kHz"
        )
        XCTAssertLessThan(
            report.decrampedError18kHzDB,
            0.05,
            "Decramped TPT SVF must match continuous-time s-domain prototype within < 0.05 dB at 18 kHz"
        )

        // (b) > 30 dB reduction in low-frequency (20 Hz, high-Q) quantization noise floor
        XCTAssertGreaterThan(
            report.noiseFloorImprovementDB,
            30.0,
            "Float64 TPT SVF must reduce 20 Hz high-Q cascade quantization noise by > 30 dB over Float32 vDSP_biquad"
        )

        // (c) Zero zipper transients above -110 dBFS during live parameter sweeps
        XCTAssertLessThan(
            report.tptSVFSweepTransientPeakDBFS,
            -110.0,
            "Per-sample smoothed TPT SVF must keep boundary zipper transients below -110 dBFS"
        )
        XCTAssertLessThan(
            report.tptSVFSweepTransientPeakDBFS,
            report.legacySweepTransientPeakDBFS - 25.0,
            "TPT SVF must substantially reduce live sweep boundary discontinuities vs unsmoothed biquad"
        )

        // (d) ITU-R BS.1770-4 True-Peak detection & limiting <= -0.1 dBTP
        XCTAssertEqual(report.rawSamplePeakDBFS, 0.0, accuracy: 0.05)
        XCTAssertGreaterThan(
            report.detectedUnonlimitedTruePeakDBTP,
            2.90,
            "4x polyphase True-Peak detector must capture +3.01 dBTP inter-sample peak"
        )
        XCTAssertLessThanOrEqual(
            report.postLimiterTruePeakDBTP,
            -0.10,
            "TruePeakLimiter must prevent all inter-sample overs above -0.10 dBTP"
        )

        // (e) p99.9 render callback latency < 10% of 64-frame @ 96 kHz quantum (< 66.7 us)
        // Shared CI VMs run a debug build with noisy neighbours, so timing is
        // only judged on a real Mac (`equmaczer --benchmark` enforces it too).
        guard ProcessInfo.processInfo.environment["CI"] == nil else { return }
        XCTAssertLessThan(
            report.p999LatencyUs,
            report.renderQuantumDeadlineUs * 0.10,
            "p99.9 callback execution must remain under 10% of 64-sample @ 96 kHz deadline"
        )
        XCTAssertTrue(report.allCriteriaPassed)
    }

    // MARK: - 2. Bijective Biquad <-> TPT SVF Isomorphism

    func testBiquadSVFBijectiveIsomorphism() {
        let sampleRate = 48000.0
        for filterType in FilterType.allCases {
            let biquad = BiquadMath.calculateCoefficients(
                type: filterType,
                sampleRate: sampleRate,
                frequency: 1250.0,
                q: 1.8,
                gain: 7.5
            )
            let svf = SVFCoefficients(biquad: biquad)
            let roundTripped = svf.toBiquadCoefficients()

            XCTAssertEqual(roundTripped.b0, biquad.b0, accuracy: 1e-11, "b0 mismatch for \(filterType)")
            XCTAssertEqual(roundTripped.b1, biquad.b1, accuracy: 1e-11, "b1 mismatch for \(filterType)")
            XCTAssertEqual(roundTripped.b2, biquad.b2, accuracy: 1e-11, "b2 mismatch for \(filterType)")
            XCTAssertEqual(roundTripped.a1, biquad.a1, accuracy: 1e-11, "a1 mismatch for \(filterType)")
            XCTAssertEqual(roundTripped.a2, biquad.a2, accuracy: 1e-11, "a2 mismatch for \(filterType)")
        }
    }

    // MARK: - 3. Analytical Transfer-Function Headroom Analyzer

    func testHeadroomAnalyzerDetectsExactResonantPeakAndRecommendsPreamp() {
        let fs = 48000.0
        let c1 = SVFMath.calculateDecrampedBiquad(
            type: .parametric,
            sampleRate: fs,
            frequency: 1000.0,
            q: 12.0,
            gain: 9.0
        )
        let c2 = SVFMath.calculateDecrampedBiquad(
            type: .parametric,
            sampleRate: fs,
            frequency: 1000.0,
            q: 4.0,
            gain: 3.0
        )

        let maxGainDB = HeadroomAnalyzer.maxCompositeGainDB(
            coefficients: [c1, c2],
            bypassFlags: [false, false],
            activeBandCount: 2,
            sampleRate: fs,
            candidateFrequencies: [1000.0]
        )

        // Stacked +9 dB and +3 dB at 1 kHz = +12.0 dB composite peak
        XCTAssertEqual(maxGainDB, 12.0, accuracy: 0.05)

        let recommendedPreamp = HeadroomAnalyzer.recommendedAutoPreampDB(
            coefficients: [c1, c2],
            bypassFlags: [false, false],
            activeBandCount: 2,
            sampleRate: fs,
            candidateFrequencies: [1000.0],
            ispSafetyMarginDB: 0.2
        )
        XCTAssertEqual(recommendedPreamp, -12.2, accuracy: 0.05)
    }

    // MARK: - 4. CoreAudio Process Tap Single-Clock Configuration

    func testProcessTapAggregateDescriptionSlavesClockToOutputDevice() {
        let tapUUID = UUID()
        let outputUID = "BuiltInSpeakerDevice"
        let tapDesc = ProcessTapCapture.makeGlobalStereoTapDescription(
            tapUUID: tapUUID,
            excludedProcessObjectIDs: [42]
        )
        XCTAssertEqual(tapDesc.uuid, tapUUID)
        XCTAssertTrue(tapDesc.isPrivate)
        XCTAssertEqual(tapDesc.muteBehavior, .mutedWhenTapped)

        let aggDesc = ProcessTapCapture.makeAggregateDeviceDescription(
            outputDeviceUID: outputUID,
            tapUUID: tapUUID
        )
        XCTAssertEqual(aggDesc[kAudioAggregateDeviceMainSubDeviceKey as String] as? String, outputUID)
        XCTAssertEqual(aggDesc[kAudioAggregateDeviceClockDeviceKey as String] as? String, outputUID)
        XCTAssertEqual(aggDesc[kAudioAggregateDeviceIsPrivateKey as String] as? Bool, true)

        let decision = CaptureModePolicy.determineMode(
            preference: .processTap,
            isManualMode: false,
            supportsSharedMemory: false
        )
        XCTAssertEqual(decision, .useMode(.processTap))
    }
}
