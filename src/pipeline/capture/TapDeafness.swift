// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// The process tap's signature failure (B1): without the
/// audio-capture permission, the tap delivers frames of digital
/// silence — the frame counter the liveness watchdog proves life
/// by advances happily. Deafness is the conjunction of three
/// facts, each necessary:
///
/// - frames advanced (the route is alive, just deaf);
/// - every input sample across the startup window sat at the
///   digital-silence floor (real content, even quiet content,
///   breaks the floor somewhere in seconds of audio);
/// - another app was producing output the tap should have heard
///   (with nothing playing anywhere, silence is the truth, not a
///   symptom).
///
/// Pure, so the rule is testable without a pipeline.
enum TapDeafness {
    /// Input RMS at or below this (dBFS) counts as digital silence.
    /// The meter storage floor is −90 dBFS.
    static let silenceFloorDB: Float = -89

    static func isDeaf(
        framesAdvanced: Bool,
        inputSamplesDB: [Float],
        otherAppProducingOutput: Bool,
        captureGranted: Bool = false
    ) -> Bool {
        // Silent helpers (WebKit, Electron) keep output "running", so silence is only
        // proof of deafness when macOS has not granted capture (sliders died, 11-21).
        !captureGranted
            && framesAdvanced
            && otherAppProducingOutput
            && !inputSamplesDB.isEmpty
            && inputSamplesDB.allSatisfy { $0 <= silenceFloorDB }
    }
}
