// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// ISO 226 equal-loudness compensation maths.
///
/// Hearing loses bass (and, less so, treble) sensitivity as the listening
/// level falls. This module computes how much extra low/high shelf gain
/// restores the tonal balance of a reference level, from the standard's
/// own formula and parameter table — not from a hand-drawn curve.
///
/// Source: ISO 226:2003, Equation (1) and Table 1 (parameters αf, LU, Tf).
/// ISO 226:2023 supersedes the 2003 edition; its contours differ by at
/// most 0.6 dB, which is well inside the uncertainty of the
/// volume-to-phon estimate this feeds (see `estimatedPhon`).
///
/// Compensation convention (shared with shipped loudness products):
/// the offset at frequency f is the contour's departure from its 1 kHz
/// value, differenced between the listening level and the reference —
/// so compensation is exactly zero at 1 kHz and only ever boosts.
enum LoudnessCompensation {
    /// Listening level (phon) at and above which no compensation applies.
    static let referencePhon = 80.0

    /// Shelf anchor frequencies the compensation gains are sampled at.
    static let lowAnchorHz = 100.0
    static let highAnchorHz = 10_000.0

    /// Hard clamps on compensation gain, however quiet it gets.
    static let maxLowBoostDB = 14.0
    static let maxHighBoostDB = 8.0

    // MARK: - ISO 226:2003 Table 1 (f, αf, LU dB, Tf dB)

    private static let table: [(f: Double, alpha: Double, lu: Double, tf: Double)] = [
        (20, 0.532, -31.6, 78.5), (25, 0.506, -27.2, 68.7), (31.5, 0.480, -23.0, 59.5),
        (40, 0.455, -19.1, 51.1), (50, 0.432, -15.9, 44.0), (63, 0.409, -13.0, 37.5),
        (80, 0.387, -10.3, 31.5), (100, 0.367, -8.1, 26.5), (125, 0.349, -6.2, 22.1),
        (160, 0.330, -4.5, 17.9), (200, 0.315, -3.1, 14.4), (250, 0.301, -2.0, 11.4),
        (315, 0.288, -1.1, 8.6), (400, 0.276, -0.4, 6.2), (500, 0.267, 0.0, 4.4),
        (630, 0.259, 0.3, 3.0), (800, 0.253, 0.5, 2.2), (1000, 0.250, 0.0, 2.4),
        (1250, 0.246, -2.7, 3.5), (1600, 0.244, -4.1, 1.7), (2000, 0.243, -1.0, -1.3),
        (2500, 0.243, 1.7, -4.2), (3150, 0.243, 2.5, -6.0), (4000, 0.242, 1.2, -5.4),
        (5000, 0.242, -2.1, -1.5), (6300, 0.245, -7.1, 6.0), (8000, 0.254, -11.2, 12.6),
        (10000, 0.271, -10.7, 13.9), (12500, 0.301, -3.1, 12.3),
    ]

    // MARK: - Contour SPL (Equation 1)

    /// Sound pressure level (dB SPL) of a pure tone at `frequency` Hz whose
    /// loudness level is `phons`, per ISO 226:2003 Equation (1).
    /// Parameters are interpolated in log-frequency between table rows;
    /// frequency is clamped to the table range (20 Hz – 12.5 kHz).
    static func spl(phons: Double, frequency: Double) -> Double {
        let (alpha, lu, tf) = parameters(at: frequency)
        let ln = max(phons, 20.0) // Equation (1) is specified from 20 phon up.
        let af = 4.47e-3 * (pow(10.0, 0.025 * ln) - 1.15)
            + pow(0.4 * pow(10.0, (tf + lu) / 10.0 - 9.0), alpha)
        return (10.0 / alpha) * log10(af) - lu + 94.0
    }

    private static func parameters(at frequency: Double) -> (alpha: Double, lu: Double, tf: Double) {
        let f = min(max(frequency, table[0].f), table[table.count - 1].f)
        for i in 0..<(table.count - 1) {
            let a = table[i], b = table[i + 1]
            if f >= a.f && f <= b.f {
                let t = (log(f) - log(a.f)) / (log(b.f) - log(a.f))
                return (
                    a.alpha + t * (b.alpha - a.alpha),
                    a.lu + t * (b.lu - a.lu),
                    a.tf + t * (b.tf - a.tf)
                )
            }
        }
        let last = table[table.count - 1]
        return (last.alpha, last.lu, last.tf)
    }

    // MARK: - Compensation

    /// Extra shelf gains that keep the tonal balance of `referencePhon`
    /// when listening at `phons`, scaled by `strength` (0...1).
    /// Returns (0, 0) at or above the reference level.
    static func compensation(phons: Double, strength: Double) -> (lowDB: Double, highDB: Double) {
        guard phons < referencePhon else { return (0, 0) }
        let s = min(max(strength, 0.0), 1.0)
        let low = contourOffset(phons: phons, frequency: lowAnchorHz)
        let high = contourOffset(phons: phons, frequency: highAnchorHz)
        return (
            min(max(low * s, 0.0), maxLowBoostDB),
            min(max(high * s, 0.0), maxHighBoostDB)
        )
    }

    /// How much more level `frequency` needs at `phons` than at the
    /// reference, relative to 1 kHz (which defines phon, so its own
    /// offset is zero by construction).
    private static func contourOffset(phons: Double, frequency: Double) -> Double {
        let atLevel = spl(phons: phons, frequency: frequency) - spl(phons: phons, frequency: 1000)
        let atReference = spl(phons: referencePhon, frequency: frequency) - spl(phons: referencePhon, frequency: 1000)
        return atLevel - atReference
    }

    // MARK: - Level estimate

    /// Estimates the listening level (phon) from the output device's
    /// volume scalar. Full volume is assumed to be a few dB above the
    /// reference (85 phon ≈ a loud home listening level); each halving
    /// of amplitude is −6 phon. This is an estimate by construction —
    /// device sensitivity varies — which is exactly what the strength
    /// control calibrates. Floored at 25 phon so compensation saturates
    /// instead of growing without bound near silence.
    static func estimatedPhon(volumeScalar: Float) -> Double {
        guard volumeScalar > 0 else { return 25.0 }
        let phon = 85.0 + 20.0 * log10(Double(volumeScalar))
        return min(max(phon, 25.0), 85.0)
    }
}
