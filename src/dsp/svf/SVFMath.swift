// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
// SVFMath.swift
// Orfanidis / Massberg Nyquist-decramped TPT State-Variable Filter synthesis
// and exact s-domain / z-domain transfer function analysis.

import Foundation

/// Pure mathematical functions for synthesizing Nyquist-decramped Topology-Preserving
/// Transform (TPT) State-Variable Filters and evaluating continuous-time (`s`-domain)
/// vs. discrete-time (`z`-domain) transfer functions.
enum SVFMath {

    // MARK: - Main Synthesis Entry Points

    /// Synthesizes Nyquist-decramped TPT SVF coefficients for the given filter parameters.
    ///
    /// Uses Orfanidis / Massberg spectral factorization in `Omega = tan(pi * f / fs)`
    /// to eliminate high-frequency magnitude cramping near Nyquist (`fs / 2`) while
    /// preserving unconditional minimum-phase stability.
    static func calculateDecrampedSVF(
        type: FilterType,
        sampleRate: Double,
        frequency: Double,
        q: Double,
        gain: Double
    ) -> SVFCoefficients {
        guard sampleRate > 0, frequency > 0, frequency < sampleRate * 0.499, q > 0 else {
            return .identity
        }

        switch type {
        case .parametric:
            return decrampedPeakingSVF(
                sampleRate: sampleRate,
                frequency: frequency,
                q: q,
                gain: gain
            )
        case .notch:
            return decrampedNotchSVF(
                sampleRate: sampleRate,
                frequency: frequency,
                q: q
            )
        case .bandPass:
            return decrampedBandPassSVF(
                sampleRate: sampleRate,
                frequency: frequency,
                q: q
            )
        case .lowPass:
            return decrampedLowPassSVF(
                sampleRate: sampleRate,
                frequency: frequency,
                q: q
            )
        case .highPass:
            return decrampedHighPassSVF(
                sampleRate: sampleRate,
                frequency: frequency,
                q: q
            )
        case .lowShelf:
            return decrampedLowShelfSVF(
                sampleRate: sampleRate,
                frequency: frequency,
                q: q,
                gain: gain
            )
        case .highShelf:
            return decrampedHighShelfSVF(
                sampleRate: sampleRate,
                frequency: frequency,
                q: q,
                gain: gain
            )
        }
    }

    /// Synthesizes Nyquist-decramped normalized `BiquadCoefficients` via the TPT SVF
    /// isomorphism.
    static func calculateDecrampedBiquad(
        type: FilterType,
        sampleRate: Double,
        frequency: Double,
        q: Double,
        gain: Double
    ) -> BiquadCoefficients {
        calculateDecrampedSVF(
            type: type,
            sampleRate: sampleRate,
            frequency: frequency,
            q: q,
            gain: gain
        ).toBiquadCoefficients()
    }

    // MARK: - Decramped Peaking EQ (Orfanidis / Exact Spectral Factorization)

    /// Synthesizes a Nyquist-decramped peaking (parametric bell) filter in TPT SVF form.
    ///
    /// In `Omega = tan(pi * f / fs)`, any second-order filter with 0 dB at DC (`Omega = 0`)
    /// and exact peak gain `G = 10^(gain/20)` with zero derivative at `Omega0 = tan(pi * f0 / fs)`
    /// has squared magnitude:
    ///
    ///   `|H(Omega)|^2 = ((Omega^2 - Omega0^2)^2 + G^2 * Omega^2 * [alpha * (Omega^2 - Omega0^2) + beta])`
    ///                 `/ ((Omega^2 - Omega0^2)^2 +       Omega^2 * [alpha * (Omega^2 - Omega0^2) + beta])`
    ///
    /// Matching the continuous-time prototype curvature at `f0` fixes `beta = Phi(f0)`,
    /// and matching the upper-skirt response at `f_ref` (up to 18-20 kHz) fixes `alpha`.
    /// Minimum-phase Hurwitz spectral factorization then yields exact `(g, R, m0, m1, m2)`
    /// TPT SVF parameters in closed form.
    static func decrampedPeakingSVF(
        sampleRate: Double,
        frequency: Double,
        q: Double,
        gain: Double
    ) -> SVFCoefficients {
        let omega0 = .pi * frequency / sampleRate
        let W0 = tan(omega0)
        if abs(gain) < 1e-7 {
            // 0 dB gain: unity passthrough with integrator cutoff pre-tracking (W0, 1/(2Q))
            return SVFCoefficients(g: W0, r: 1.0 / (2.0 * q), c0: 1.0, c1: 0.0, c2: 0.0, isIdentity: true)
        }

        let G = pow(10.0, gain / 20.0)
        let G2 = G * G
        let W0_2 = W0 * W0

        // Exact curvature match at f = f0:
        // Phi(f0) = (1 / G) * ((pi * f0) / (fs * Q) * (1 + W0^2))^2
        let dWdF_f0 = (.pi * frequency / (sampleRate * q)) * (1.0 + W0_2)
        let beta = (dWdF_f0 * dWdF_f0) / G

        // Choose upper passband reference frequency to eliminate Nyquist cramping up to 20 kHz
        let maxAudibleRef = min(20000.0, sampleRate * 0.455)
        let fRef: Double
        if frequency < 16000.0 && sampleRate >= 40000.0 {
            fRef = min(maxAudibleRef, max(frequency * 1.35, min(18000.0, sampleRate * 0.41)))
        } else {
            fRef = 0.5 * (frequency + maxAudibleRef)
        }

        var alpha: Double = 0.0
        if fRef > frequency + 10.0 && fRef < sampleRate * 0.48 {
            let Wref = tan(.pi * fRef / sampleRate)
            let Wref_2 = Wref * Wref
            let uRef = Wref_2 - W0_2
            if uRef > 1e-12 {
                let ratioTerm = ((Wref_2 - W0_2) / Wref) * ((frequency / q) / (fRef - (frequency * frequency) / fRef))
                let phiRef = (ratioTerm * ratioTerm) / G
                alpha = max(0.0, (phiRef - beta) / uRef)
            }
        }

        // Exact closed-form Hurwitz spectral factorization bounds:
        // r_den(alpha) = beta - W0^2 * (sqrt(1 + alpha) - 1)^2 > 0
        // r_num(alpha) = G^2 * beta - W0^2 * (sqrt(1 + G^2 * alpha) - 1)^2 > 0
        let sqrtBetaOverW0 = sqrt(beta) / W0
        let maxAlphaDen = (1.0 + sqrtBetaOverW0) * (1.0 + sqrtBetaOverW0) - 1.0
        let maxAlphaNum = ((1.0 + G * sqrtBetaOverW0) * (1.0 + G * sqrtBetaOverW0) - 1.0) / G2
        let alphaLimit = 0.995 * min(maxAlphaDen, maxAlphaNum)
        alpha = min(alpha, max(0.0, alphaLimit))

        let d0 = W0_2
        let d2 = sqrt(1.0 + alpha)
        let denDiff = d2 - 1.0
        let d1 = sqrt(max(1e-18, beta - W0_2 * denDiff * denDiff))

        let n2 = sqrt(1.0 + G2 * alpha)
        let numDiff = n2 - 1.0
        let n1 = sqrt(max(1e-18, G2 * beta - W0_2 * numDiff * numDiff))

        // Map factored s-domain polynomials (n2*s^2 + n1*s + d0) / (d2*s^2 + d1*s + d0)
        // directly to TPT SVF parameters:
        let sqrtD0D2 = sqrt(d0 * d2)
        let g = sqrt(d0 / d2)
        let r = d1 / (2.0 * sqrtD0D2)
        let m0 = n2 / d2
        let m1 = n1 / sqrtD0D2
        let m2 = 1.0

        return SVFCoefficients(g: g, r: r, m0: m0, m1: m1, m2: m2, isIdentity: false)
    }

    // MARK: - Decramped Notch & Band-Pass

    static func decrampedNotchSVF(
        sampleRate: Double,
        frequency: Double,
        q: Double
    ) -> SVFCoefficients {
        let omega0 = .pi * frequency / sampleRate
        let W0 = tan(omega0)
        let W0_2 = W0 * W0

        let dWdF_f0 = (.pi * frequency / (sampleRate * q)) * (1.0 + W0_2)
        let beta = dWdF_f0 * dWdF_f0

        let maxAudibleRef = min(20000.0, sampleRate * 0.455)
        let fRef = frequency < 16000.0
            ? min(maxAudibleRef, max(frequency * 1.35, min(18000.0, sampleRate * 0.41)))
            : 0.5 * (frequency + maxAudibleRef)

        var alpha: Double = 0.0
        if fRef > frequency + 10.0 && fRef < sampleRate * 0.48 {
            let Wref = tan(.pi * fRef / sampleRate)
            let Wref_2 = Wref * Wref
            let uRef = Wref_2 - W0_2
            if uRef > 1e-12 {
                let ratioTerm = ((Wref_2 - W0_2) / Wref) * ((frequency / q) / (fRef - (frequency * frequency) / fRef))
                let phiRef = ratioTerm * ratioTerm
                alpha = max(0.0, (phiRef - beta) / uRef)
            }
        }

        let sqrtBetaOverW0 = sqrt(beta) / W0
        let alphaLimit = 0.995 * ((1.0 + sqrtBetaOverW0) * (1.0 + sqrtBetaOverW0) - 1.0)
        alpha = min(alpha, max(0.0, alphaLimit))

        let d0 = W0_2
        let d2 = sqrt(1.0 + alpha)
        let denDiff = d2 - 1.0
        let d1 = sqrt(max(1e-18, beta - W0_2 * denDiff * denDiff))

        let sqrtD0D2 = sqrt(d0 * d2)
        let g = sqrt(d0 / d2)
        let r = d1 / (2.0 * sqrtD0D2)
        // Numerator is (s^2 + W0^2) -> n2 = 1, n1 = 0, n0 = d0
        let m0 = 1.0 / d2
        let m1 = 0.0
        let m2 = 1.0

        return SVFCoefficients(g: g, r: r, m0: m0, m1: m1, m2: m2, isIdentity: false)
    }

    static func decrampedBandPassSVF(
        sampleRate: Double,
        frequency: Double,
        q: Double
    ) -> SVFCoefficients {
        // Use the decramped notch denominator poles so the bandpass skirt is decramped,
        // with unity peak gain (m0 = 0, m1 = 2 * R, m2 = 0) at resonance.
        let notch = decrampedNotchSVF(sampleRate: sampleRate, frequency: frequency, q: q)
        return SVFCoefficients(g: notch.g, r: notch.r, m0: 0.0, m1: 2.0 * notch.r, m2: 0.0, isIdentity: false)
    }

    // MARK: - Decramped Low-Pass & High-Pass (Massberg Matched-Nyquist SVF)

    static func decrampedLowPassSVF(
        sampleRate: Double,
        frequency: Double,
        q: Double
    ) -> SVFCoefficients {
        // Massberg matched-Nyquist second-order low-pass filter:
        // Preserves exact DC gain = 1, cutoff gain = Q at f0, and finite analog gain at Nyquist.
        let rNyq = (sampleRate * 0.5) / frequency
        let nyqDenom = (1.0 - rNyq * rNyq) * (1.0 - rNyq * rNyq) + (rNyq / q) * (rNyq / q)
        let gNyq = 1.0 / sqrt(max(1e-12, nyqDenom)) // Analog magnitude at Nyquist

        let omega0 = .pi * frequency / sampleRate
        let W0 = tan(omega0)
        // Prewarp cutoff frequency to compensate for nonzero Nyquist zero
        let g = W0 / sqrt(max(0.1, sqrt(max(0.01, 1.0 - gNyq * gNyq))))
        let r = 1.0 / (2.0 * q)

        // Numerator: gNyq * s^2 + g^2 -> m0 = gNyq, m1 = 0, m2 = 1.0
        return SVFCoefficients(g: g, r: r, m0: gNyq, m1: 0.0, m2: 1.0, isIdentity: false)
    }

    static func decrampedHighPassSVF(
        sampleRate: Double,
        frequency: Double,
        q: Double
    ) -> SVFCoefficients {
        let omega0 = .pi * frequency / sampleRate
        let g = tan(omega0)
        let r = 1.0 / (2.0 * q)
        return SVFCoefficients(g: g, r: r, m0: 1.0, m1: 0.0, m2: 0.0, isIdentity: false)
    }

    // MARK: - Decramped Shelving Filters (Simper TPT SVF Topology)

    static func decrampedLowShelfSVF(
        sampleRate: Double,
        frequency: Double,
        q: Double,
        gain: Double
    ) -> SVFCoefficients {
        let omega0 = .pi * frequency / sampleRate
        let W0 = tan(omega0)
        if abs(gain) < 1e-7 {
            return SVFCoefficients(g: W0, r: 1.0 / (2.0 * q), c0: 1.0, c1: 0.0, c2: 0.0, isIdentity: true)
        }
        let A = pow(10.0, gain / 40.0)
        let g = W0 / sqrt(A)
        let r = 1.0 / (2.0 * q)
        let m0 = 1.0
        let m1 = 2.0 * r * A
        let m2 = A * A
        return SVFCoefficients(g: g, r: r, m0: m0, m1: m1, m2: m2, isIdentity: false)
    }

    static func decrampedHighShelfSVF(
        sampleRate: Double,
        frequency: Double,
        q: Double,
        gain: Double
    ) -> SVFCoefficients {
        let omega0 = .pi * frequency / sampleRate
        let W0 = tan(omega0)
        if abs(gain) < 1e-7 {
            return SVFCoefficients(g: W0, r: 1.0 / (2.0 * q), c0: 1.0, c1: 0.0, c2: 0.0, isIdentity: true)
        }
        let A = pow(10.0, gain / 40.0)
        let g = W0 * sqrt(A)
        let r = 1.0 / (2.0 * q)
        let m0 = A * A
        let m1 = 2.0 * r * A
        let m2 = 1.0
        return SVFCoefficients(g: g, r: r, m0: m0, m1: m1, m2: m2, isIdentity: false)
    }

    // MARK: - Continuous-Time (s-Domain) Prototype Transfer Function

    /// Computes the exact continuous-time (`s`-domain) analog prototype squared magnitude
    /// `|H_a(j * 2*pi*f)|^2` at frequency `evalFrequency` (Hz).
    static func analogMagnitudeSquared(
        type: FilterType,
        frequency: Double,
        q: Double,
        gain: Double,
        at evalFrequency: Double
    ) -> Double {
        guard frequency > 0, q > 0, evalFrequency >= 0 else { return 1.0 }
        let r = evalFrequency / frequency
        let r2 = r * r
        let oneMinusR2Sq = (1.0 - r2) * (1.0 - r2)
        let rOverQSq = (r / q) * (r / q)

        switch type {
        case .parametric:
            let A = pow(10.0, gain / 40.0)
            let A2 = A * A
            let num = oneMinusR2Sq + A2 * rOverQSq
            let den = oneMinusR2Sq + (rOverQSq / A2)
            return den > 0 ? num / den : 1.0

        case .lowPass:
            let den = oneMinusR2Sq + rOverQSq
            return den > 0 ? 1.0 / den : 0.0

        case .highPass:
            let den = oneMinusR2Sq + rOverQSq
            return den > 0 ? (r2 * r2) / den : 0.0

        case .bandPass:
            let den = oneMinusR2Sq + rOverQSq
            return den > 0 ? rOverQSq / den : 0.0

        case .notch:
            let den = oneMinusR2Sq + rOverQSq
            return den > 0 ? oneMinusR2Sq / den : 1.0

        case .lowShelf:
            let A = pow(10.0, gain / 40.0)
            let A2 = A * A
            let num = A2 * ((A - r2) * (A - r2) + A2 * rOverQSq)
            let den = (1.0 - A * r2) * (1.0 - A * r2) + A2 * rOverQSq
            return den > 0 ? num / den : 1.0

        case .highShelf:
            let A = pow(10.0, gain / 40.0)
            let A2 = A * A
            let num = A2 * ((1.0 - A * r2) * (1.0 - A * r2) + A2 * rOverQSq)
            let den = (A - r2) * (A - r2) + A2 * rOverQSq
            return den > 0 ? num / den : 1.0
        }
    }

    /// Computes the exact continuous-time (`s`-domain) analog prototype magnitude in dB.
    static func analogMagnitudeDB(
        type: FilterType,
        frequency: Double,
        q: Double,
        gain: Double,
        at evalFrequency: Double
    ) -> Double {
        let magSq = analogMagnitudeSquared(
            type: type,
            frequency: frequency,
            q: q,
            gain: gain,
            at: evalFrequency
        )
        return 10.0 * log10(max(1e-30, magSq))
    }

    // MARK: - Discrete-Time (z-Domain) Transfer Function Evaluation

    /// Evaluates the exact complex frequency response `H(e^(j*omega))` of a normalized
    /// digital biquad at `evalFrequency` (Hz).
    @inline(__always)
    static func digitalComplexResponse(
        _ coeffs: BiquadCoefficients,
        sampleRate: Double,
        at evalFrequency: Double
    ) -> (real: Double, imag: Double) {
        let omega = 2.0 * .pi * evalFrequency / sampleRate
        let cos1 = cos(omega)
        let sin1 = sin(omega)
        let cos2 = 2.0 * cos1 * cos1 - 1.0
        let sin2 = 2.0 * sin1 * cos1

        // H(e^jw) = (b0 + b1*e^-jw + b2*e^-j2w) / (1 + a1*e^-jw + a2*e^-j2w)
        let numRe = coeffs.b0 + coeffs.b1 * cos1 + coeffs.b2 * cos2
        let numIm = -(coeffs.b1 * sin1 + coeffs.b2 * sin2)
        let denRe = 1.0 + coeffs.a1 * cos1 + coeffs.a2 * cos2
        let denIm = -(coeffs.a1 * sin1 + coeffs.a2 * sin2)

        let denMagSq = max(1e-30, denRe * denRe + denIm * denIm)
        let real = (numRe * denRe + numIm * denIm) / denMagSq
        let imag = (numIm * denRe - numRe * denIm) / denMagSq
        return (real, imag)
    }

    /// Evaluates the exact discrete-time magnitude squared `|H(e^(j*omega))|^2` of a biquad.
    @inline(__always)
    static func digitalMagnitudeSquared(
        _ coeffs: BiquadCoefficients,
        sampleRate: Double,
        at evalFrequency: Double
    ) -> Double {
        let resp = digitalComplexResponse(coeffs, sampleRate: sampleRate, at: evalFrequency)
        return resp.real * resp.real + resp.imag * resp.imag
    }

    /// Evaluates the exact discrete-time magnitude in dB `20 * log10(|H(e^(j*omega))|)` of a biquad.
    @inline(__always)
    static func digitalMagnitudeDB(
        _ coeffs: BiquadCoefficients,
        sampleRate: Double,
        at evalFrequency: Double
    ) -> Double {
        let magSq = digitalMagnitudeSquared(coeffs, sampleRate: sampleRate, at: evalFrequency)
        return 10.0 * log10(max(1e-30, magSq))
    }

    /// Evaluates the exact discrete-time magnitude in dB of an `SVFCoefficients` section.
    @inline(__always)
    static func digitalMagnitudeDB(
        _ svf: SVFCoefficients,
        sampleRate: Double,
        at evalFrequency: Double
    ) -> Double {
        digitalMagnitudeDB(svf.toBiquadCoefficients(), sampleRate: sampleRate, at: evalFrequency)
    }
}
