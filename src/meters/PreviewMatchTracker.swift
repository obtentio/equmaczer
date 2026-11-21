// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// Level-matching maths for correction previews (A1), kept pure
/// like `LoudnessMeter`'s so it is tested directly.
///
/// The paired BS.1770 delta describes how much loudness the whole
/// EQ path adds. The saved sound's delta is the reference; the
/// preview's delta, once the meter has converged under it, says how
/// much louder or quieter the preview runs. The offset that makes
/// the comparison fair is the difference, clamped to the same
/// ±12 dB the matched bypass uses. It is programme-dependent by
/// nature — it describes the music that played while it settled —
/// exactly as the matched bypass delta is.
enum PreviewMatchTracker {
    /// Largest broadband shift matching may apply, either way.
    static let maxOffsetDB = 12.0

    /// Offset (dB) to fold into the preview so its loudness meets
    /// the reference: positive raises the preview, negative lowers.
    static func offsetDB(referenceDeltaDB: Double, currentDeltaDB: Double) -> Double {
        min(maxOffsetDB, max(-maxOffsetDB, referenceDeltaDB - currentDeltaDB))
    }

    /// The preamp the preview composes with while matched: its
    /// published preamp plus the offset, never above 0 dB — a
    /// correction preamp is headroom, and matching may spend it but
    /// never go into debt against it. (The headroom analysis in
    /// `CorrectionController.refresh()` can still demand a lower,
    /// more protective value on top of this.)
    static func matchedPreampDB(publishedPreampDB: Float, offsetDB: Double) -> Float {
        min(0, publishedPreampDB + Float(offsetDB))
    }
}
