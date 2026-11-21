// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// Dose maths (A6), pure. The reference is the WHO–ITU weekly
/// exposure budget: 80 dBA for 40 hours, with a 3 dB exchange rate
/// (every +3 dB halves the allowed time).
///
/// The level fed into it is an *estimate*, built from the two facts
/// the app knows — its own output level in dBFS and the output
/// device's volume — plus one stated anchor: full-scale output at
/// full device volume counts as 100 dBA at the ear. The anchor is
/// printed on the dose view; nothing here pretends the result is a
/// measurement.
enum DoseMath {
    static let referenceLevelDBA = 80.0
    static let referenceHours = 40.0
    static let anchorDB = 100.0

    /// Estimated listening level from the app's output RMS and the
    /// device volume (already in dB; 0 when unknown, which reads as
    /// full volume — the conservative direction).
    static func estimatedLevelDBA(outputRmsDBFS: Double, volumeDB: Double) -> Double {
        outputRmsDBFS + volumeDB + anchorDB
    }

    /// Seconds of exposure at `levelDBA` that spend the whole
    /// weekly reference budget.
    static func allowedSeconds(levelDBA: Double) -> Double {
        referenceHours * 3600 * pow(2.0, (referenceLevelDBA - levelDBA) / 3.0)
    }

    /// The fraction of the weekly budget that `durationSeconds` at
    /// `levelDBA` spends.
    static func doseFraction(levelDBA: Double, durationSeconds: Double) -> Double {
        guard durationSeconds > 0 else { return 0 }
        return durationSeconds / allowedSeconds(levelDBA: levelDBA)
    }
}
