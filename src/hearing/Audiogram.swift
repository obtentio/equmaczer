// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

enum HearingEar: String, Codable, CaseIterable {
    case left, right

    var letter: String { self == .left ? "L" : "R" }
}

/// A listener-entered audiogram: one threshold per standard
/// audiometric frequency per ear, in dB HL. Pure value type.
///
/// The compensation is a rough estimate, never a prescription: each
/// bell gets half the loss above `normalLimitDB` (the classic
/// half-gain rule of thumb), capped at the hearing layer's own range.
struct Audiogram: Codable, Equatable {
    /// Standard audiometric frequencies used here, Hz.
    static let frequencies: [Float] = [250, 500, 1000, 2000, 4000, 8000]
    /// Entry range, dB HL.
    static let rangeDB: ClosedRange<Float> = -10...90
    static let stepDB: Float = 5
    /// Thresholds at or below this are treated as normal: no boost.
    static let normalLimitDB: Float = 15
    /// Share of the loss above the limit that is compensated.
    static let gainFraction: Float = 0.5
    /// One-octave-spaced bells overlap into a smooth curve.
    static let bellQ: Float = 1.0

    var leftDB: [Float] = Array(repeating: 0, count: Audiogram.frequencies.count)
    var rightDB: [Float] = Array(repeating: 0, count: Audiogram.frequencies.count)
    /// Whether the hearing layer follows this audiogram instead of
    /// the by-ear shelves.
    var inUse = true

    func thresholds(for ear: HearingEar) -> [Float] {
        ear == .left ? leftDB : rightDB
    }

    mutating func setThreshold(_ db: Float, ear: HearingEar, index: Int) {
        guard Self.frequencies.indices.contains(index) else { return }
        let clamped = min(max(db, Self.rangeDB.lowerBound), Self.rangeDB.upperBound)
        if ear == .left { leftDB[index] = clamped } else { rightDB[index] = clamped }
    }

    /// An ear counts as entered once any of its thresholds is set.
    func isEntered(_ ear: HearingEar) -> Bool {
        thresholds(for: ear).contains { $0 != 0 }
    }

    var enteredEars: [HearingEar] { HearingEar.allCases.filter(isEntered) }

    /// The boost one threshold earns, dB.
    static func compensationDB(forThreshold db: Float) -> Float {
        let gain = max(0, db - normalLimitDB) * gainFraction
        return min(gain, HearingState.rangeDB.upperBound)
    }

    /// The per-ear curve: one bell per frequency that needs a boost.
    func bands(for ear: HearingEar) -> [EQBandConfiguration] {
        var bands: [EQBandConfiguration] = []
        for (index, frequency) in Self.frequencies.enumerated() {
            let gain = Self.compensationDB(forThreshold: thresholds(for: ear)[index])
            guard gain != 0 else { continue }
            bands.append(EQBandConfiguration(
                frequency: frequency, q: Self.bellQ, gain: gain, filterType: .parametric, bypass: false
            ))
        }
        return bands
    }
}
