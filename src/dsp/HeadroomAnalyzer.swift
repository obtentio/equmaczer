// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
// HeadroomAnalyzer.swift
// Analytical transfer-function peak gain and auto-preamp headroom calculator.

import Foundation

/// Evaluates the exact composite complex transfer function `H_total(e^(j*omega))`
/// of an EQ filter cascade to determine worst-case peak boost and required auto-preamp
/// headroom attenuation.
enum HeadroomAnalyzer {

    /// Computes the maximum composite magnitude gain (in dB) of a cascade of normalized
    /// biquad filter sections across the audible spectrum `[10 Hz, fs / 2)`.
    ///
    /// Evaluates a 512-point logarithmic frequency grid plus exact resonant pole/peak
    /// frequencies so narrow high-`Q` peaks are never missed between grid points.
    static func maxCompositeGainDB(
        coefficients: [BiquadCoefficients],
        bypassFlags: [Bool],
        activeBandCount: Int,
        sampleRate: Double,
        candidateFrequencies: [Double] = []
    ) -> Double {
        guard sampleRate > 0, activeBandCount > 0 else { return 0.0 }

        var activeCoeffs: [BiquadCoefficients] = []
        let limit = min(activeBandCount, min(coefficients.count, bypassFlags.count))
        for i in 0..<limit {
            if !bypassFlags[i] && coefficients[i] != .identity {
                activeCoeffs.append(coefficients[i])
            }
        }
        guard !activeCoeffs.isEmpty else { return 0.0 }

        let minFreq = 10.0
        let maxFreq = sampleRate * 0.498
        let gridPoints = 512
        let logRatio = log(maxFreq / minFreq)

        var maxMagSq: Double = 0.0

        // 1. Evaluate 512-point logarithmic grid
        for k in 0..<gridPoints {
            let t = Double(k) / Double(gridPoints - 1)
            let freq = minFreq * exp(t * logRatio)
            let magSq = compositeMagnitudeSquared(activeCoeffs, sampleRate: sampleRate, at: freq)
            if magSq > maxMagSq {
                maxMagSq = magSq
            }
        }

        // 2. Evaluate exact band center frequencies so high-Q peaks are sampled at their crest
        for freq in candidateFrequencies where freq >= minFreq && freq <= maxFreq {
            let magSq = compositeMagnitudeSquared(activeCoeffs, sampleRate: sampleRate, at: freq)
            if magSq > maxMagSq {
                maxMagSq = magSq
            }
        }

        return 10.0 * log10(max(1e-30, maxMagSq))
    }

    /// Computes the recommended negative auto-preamp gain (in dB) to prevent positive
    /// transfer-function boosts and phase-rotation inter-sample overs from clipping a 0 dBFS input.
    ///
    /// - Parameters:
    ///   - coefficients: Active biquad sections.
    ///   - bypassFlags: Per-band bypass flags.
    ///   - activeBandCount: Number of active bands.
    ///   - sampleRate: Sample rate in Hz.
    ///   - candidateFrequencies: Center frequencies of active bands.
    ///   - ispSafetyMarginDB: Additional safety margin for phase-dispersive inter-sample peaks
    ///     when filters are active (default `0.2 dB`).
    /// - Returns: Recommended preamp gain in dB (`<= 0.0`).
    static func recommendedAutoPreampDB(
        coefficients: [BiquadCoefficients],
        bypassFlags: [Bool],
        activeBandCount: Int,
        sampleRate: Double,
        candidateFrequencies: [Double] = [],
        ispSafetyMarginDB: Double = 0.2
    ) -> Double {
        let maxGainDB = maxCompositeGainDB(
            coefficients: coefficients,
            bypassFlags: bypassFlags,
            activeBandCount: activeBandCount,
            sampleRate: sampleRate,
            candidateFrequencies: candidateFrequencies
        )
        if maxGainDB <= 0.001 {
            return 0.0
        }
        return -(maxGainDB + ispSafetyMarginDB)
    }

    // MARK: - SVF-Native Entry Points

    /// SVF-coefficient variant of `maxCompositeGainDB(coefficients:...)`.
    ///
    /// The conversion to biquads happens here, on the analysis path only —
    /// staged coefficients reach the audio thread as native SVF parameters
    /// and are never round-tripped through the biquad isomorphism.
    static func maxCompositeGainDB(
        svfCoefficients: [SVFCoefficients],
        bypassFlags: [Bool],
        activeBandCount: Int,
        sampleRate: Double,
        candidateFrequencies: [Double] = []
    ) -> Double {
        maxCompositeGainDB(
            coefficients: svfCoefficients.map { $0.toBiquadCoefficients() },
            bypassFlags: bypassFlags,
            activeBandCount: activeBandCount,
            sampleRate: sampleRate,
            candidateFrequencies: candidateFrequencies
        )
    }

    /// SVF-coefficient variant of `recommendedAutoPreampDB(coefficients:...)`.
    static func recommendedAutoPreampDB(
        svfCoefficients: [SVFCoefficients],
        bypassFlags: [Bool],
        activeBandCount: Int,
        sampleRate: Double,
        candidateFrequencies: [Double] = [],
        ispSafetyMarginDB: Double = 0.2
    ) -> Double {
        recommendedAutoPreampDB(
            coefficients: svfCoefficients.map { $0.toBiquadCoefficients() },
            bypassFlags: bypassFlags,
            activeBandCount: activeBandCount,
            sampleRate: sampleRate,
            candidateFrequencies: candidateFrequencies,
            ispSafetyMarginDB: ispSafetyMarginDB
        )
    }

    /// The composite magnitude (dB) on the same fixed 512-point log
    /// grid `maxCompositeGainDB` evaluates (10 Hz to 0.498 · fs),
    /// without the candidate-frequency refinement. Two layers
    /// evaluated at the same sample rate produce point-aligned
    /// vectors, so the cascade peak of layered stages (manual EQ +
    /// correction) can be taken from the summed vector instead of
    /// summing the layers' separate peaks — the sum of peaks
    /// over-cuts whenever the layers peak at different frequencies.
    static func compositeMagnitudeDBVector(
        svfCoefficients: [SVFCoefficients],
        bypassFlags: [Bool],
        activeBandCount: Int,
        sampleRate: Double
    ) -> [Float] {
        let gridPoints = 512
        guard sampleRate > 0, activeBandCount > 0 else {
            return [Float](repeating: 0, count: gridPoints)
        }
        let coefficients = svfCoefficients.map { $0.toBiquadCoefficients() }
        var activeCoeffs: [BiquadCoefficients] = []
        let limit = min(activeBandCount, min(coefficients.count, bypassFlags.count))
        for i in 0..<limit {
            if !bypassFlags[i] && coefficients[i] != .identity {
                activeCoeffs.append(coefficients[i])
            }
        }
        guard !activeCoeffs.isEmpty else {
            return [Float](repeating: 0, count: gridPoints)
        }
        let minFreq = 10.0
        let maxFreq = sampleRate * 0.498
        let logRatio = log(maxFreq / minFreq)
        var vector = [Float](repeating: 0, count: gridPoints)
        for k in 0..<gridPoints {
            let t = Double(k) / Double(gridPoints - 1)
            let freq = minFreq * exp(t * logRatio)
            let magSq = compositeMagnitudeSquared(activeCoeffs, sampleRate: sampleRate, at: freq)
            vector[k] = Float(10.0 * log10(max(1e-30, magSq)))
        }
        return vector
    }

    /// Composite gain (dB) of an SVF cascade at a single frequency — the
    /// per-point evaluator behind `maxCompositeGainDB`, exposed for the
    /// main window's composite curve display.
    static func compositeGainDB(
        svfCoefficients: [SVFCoefficients],
        bypassFlags: [Bool],
        activeBandCount: Int,
        sampleRate: Double,
        at frequency: Double
    ) -> Double {
        guard sampleRate > 0, activeBandCount > 0 else { return 0.0 }

        var activeCoeffs: [BiquadCoefficients] = []
        let limit = min(activeBandCount, min(svfCoefficients.count, bypassFlags.count))
        for i in 0..<limit where !bypassFlags[i] {
            let coefficients = svfCoefficients[i].toBiquadCoefficients()
            if coefficients != .identity {
                activeCoeffs.append(coefficients)
            }
        }
        guard !activeCoeffs.isEmpty else { return 0.0 }

        let magSq = compositeMagnitudeSquared(activeCoeffs, sampleRate: sampleRate, at: frequency)
        return 10.0 * log10(max(1e-30, magSq))
    }

    @inline(__always)
    private static func compositeMagnitudeSquared(
        _ coeffs: [BiquadCoefficients],
        sampleRate: Double,
        at frequency: Double
    ) -> Double {
        var totalMagSq = 1.0
        for c in coeffs {
            totalMagSq *= SVFMath.digitalMagnitudeSquared(c, sampleRate: sampleRate, at: frequency)
        }
        return totalMagSq
    }
}
