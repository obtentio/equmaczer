// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
// SVFCoefficients.swift
// Double-precision Topology-Preserving Transform (TPT) State-Variable Filter coefficients.

import Foundation

/// Coefficients for a second-order Topology-Preserving Transform (TPT)
/// State-Variable Filter (Andrew Simper / Cytomic / Vadim Zavalishin topology).
///
/// In the normalized trapezoidal integrator domain `s = (z - 1) / (z + 1)`:
///   `H(s) = (m0 * s^2 + m1 * g * s + m2 * g^2) / (s^2 + 2 * R * g * s + g^2)`
///
/// The per-sample state update using trapezoidal integrators (`ic1eq`, `ic2eq`) is:
/// ```
/// v3 = x - ic2eq
/// v1 = a1 * ic1eq + a2 * v3
/// v2 = ic2eq + a2 * ic1eq + a3 * v3
/// ic1eq = 2 * v1 - ic1eq
/// ic2eq = 2 * v2 - ic2eq
/// y = c0 * x + c1 * v1 + c2 * v2
/// ```
/// where:
/// - `a1 = 1 / (1 + g * (g + 2 * R))`
/// - `a2 = g * a1`
/// - `a3 = g * a2`
/// - `c0 = m0`, `c1 = m1 - 2 * R * m0`, `c2 = m2 - m0`
///
/// Unlike Direct Form I/II biquads:
/// 1. Pole quantization noise at low frequencies (`f0 << fs`) scales as `O(1 / w0)`
///    instead of `O(1 / w0^2)`, and internal `Float64` state provides 53-bit mantissa precision.
/// 2. Cutoff gain `g`, damping `R`, and output mix weights `(c0, c1, c2)` can be smoothly
///    interpolated per-sample without poles ever leaving the unit circle or causing state
///    scaling transients (zipper noise).
struct SVFCoefficients: Sendable, Equatable {
    /// Trapezoidal integrator cutoff gain (`g > 0`).
    let g: Double
    /// Damping factor (`R = 1 / (2 * Q_eff) > 0`).
    let r: Double
    /// Direct input mix weight (`c0 = m0`).
    let c0: Double
    /// Band-pass integrator state output weight (`c1 = m1 - 2 * R * m0`).
    let c1: Double
    /// Low-pass integrator state output weight (`c2 = m2 - m0`).
    let c2: Double
    /// Precomputed integrator gain `a1 = 1 / (1 + g * (g + 2 * r))`.
    let a1: Double
    /// Precomputed integrator gain `a2 = g * a1`.
    let a2: Double
    /// Precomputed integrator gain `a3 = g * a2`.
    let a3: Double
    /// Whether this section is exact unity passthrough (`H(z) = 1`).
    let isIdentity: Bool

    /// Exact unity passthrough (`y = x`) with critically damped unit integrator state.
    static let identity = SVFCoefficients(
        g: 1.0,
        r: 1.0,
        c0: 1.0,
        c1: 0.0,
        c2: 0.0,
        isIdentity: true
    )

    /// Creates TPT SVF coefficients from `(g, r, c0, c1, c2)`.
    @inline(__always)
    init(
        g: Double,
        r: Double,
        c0: Double,
        c1: Double,
        c2: Double,
        isIdentity: Bool = false
    ) {
        let safeG = max(1e-9, g)
        let safeR = max(1e-7, r)
        let a1Val = 1.0 / (1.0 + safeG * (safeG + 2.0 * safeR))
        let a2Val = safeG * a1Val
        let a3Val = safeG * a2Val

        self.g = safeG
        self.r = safeR
        self.c0 = c0
        self.c1 = c1
        self.c2 = c2
        self.a1 = a1Val
        self.a2 = a2Val
        self.a3 = a3Val
        self.isIdentity = isIdentity
    }

    /// Creates TPT SVF coefficients from modal weights `(g, r, m0, m1, m2)` where
    /// `y = m0 * HP + m1 * BP + m2 * LP`.
    @inline(__always)
    init(g: Double, r: Double, m0: Double, m1: Double, m2: Double, isIdentity: Bool = false) {
        let c0 = m0
        let c1 = m1 - 2.0 * r * m0
        let c2 = m2 - m0
        self.init(g: g, r: r, c0: c0, c1: c1, c2: c2, isIdentity: isIdentity)
    }

    /// Bijective algebraic conversion from normalized `BiquadCoefficients`
    /// `H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)`
    /// into exact TPT SVF parameters via the bilinear identity `z^-1 = (1 - s) / (1 + s)`.
    init(biquad: BiquadCoefficients) {
        if biquad == .identity {
            self = .identity
            return
        }

        let b0 = biquad.b0
        let b1 = biquad.b1
        let b2 = biquad.b2
        let a1 = biquad.a1
        let a2 = biquad.a2

        // In s = (z - 1) / (z + 1):
        // D(s) = (1 - a1 + a2) * s^2 + 2 * (1 - a2) * s + (1 + a1 + a2)
        // N(s) = (b0 - b1 + b2) * s^2 + 2 * (b0 - b2) * s + (b0 + b1 + b2)
        let d2 = max(1e-15, 1.0 - a1 + a2)
        let d1 = max(1e-15, 2.0 * (1.0 - a2))
        let d0 = max(1e-15, 1.0 + a1 + a2)

        let n2 = b0 - b1 + b2
        let n1 = 2.0 * (b0 - b2)
        let n0 = b0 + b1 + b2

        let g = sqrt(d0 / d2)
        let r = d1 / (2.0 * sqrt(d0 * d2))

        let m0 = n2 / d2
        let m1 = n1 / sqrt(d0 * d2)
        let m2 = n0 / d0

        let isId = abs(c0From(m0: m0) - 1.0) < 1e-12
            && abs(m1 - 2.0 * r * m0) < 1e-12
            && abs(m2 - m0) < 1e-12

        self.init(g: g, r: r, m0: m0, m1: m1, m2: m2, isIdentity: isId)
    }

    /// Converts TPT SVF parameters back into normalized `BiquadCoefficients`
    /// `H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)`.
    func toBiquadCoefficients() -> BiquadCoefficients {
        if isIdentity {
            return .identity
        }
        let m0 = c0
        let m1 = c1 + 2.0 * r * c0
        let m2 = c2 + c0

        let g2 = g * g
        let twoRG = 2.0 * r * g
        let denom = 1.0 + twoRG + g2
        let invDenom = 1.0 / denom

        let b0 = (m0 + m1 * g + m2 * g2) * invDenom
        let b1 = 2.0 * (m2 * g2 - m0) * invDenom
        let b2 = (m0 - m1 * g + m2 * g2) * invDenom
        let a1 = 2.0 * (g2 - 1.0) * invDenom
        let a2 = (1.0 - twoRG + g2) * invDenom

        return BiquadCoefficients(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }
}

@inline(__always)
private func c0From(m0: Double) -> Double { m0 }
