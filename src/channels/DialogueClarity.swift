// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// Dialogue mode (A4): the speech-clarity band set composed into
/// the channel layer after the treatment's bands, for the channels
/// that carry speech worth following (Film, Calls — see
/// `AudioChannel.supportsDialogue`).
///
/// The shape follows dialogue-enhancement practice, kept modest on
/// purpose: energy below the speech fundamentals is masking rather
/// than voice, intelligibility is decided in the consonant region
/// around 2–4 kHz, and a little top definition helps without
/// harshness. One fixed curve — strength belongs to the blend
/// control (C3), not here. What this is not: Fraunhofer's full
/// programme also measures speech loudness and re-mixes dialogue
/// against background from separated stems; a tapped stereo mix has
/// no stems, so the honest slice is the presence half (see the A4
/// plan for what was deliberately left out).
enum DialogueClarity {
    static let bands: [EQBandConfiguration] = [
        EQBandConfiguration(
            frequency: 200, q: 0.9, gain: -2,
            filterType: .lowShelf, bypass: false
        ),
        EQBandConfiguration(
            frequency: 2800, q: 0.9, gain: 3.5,
            filterType: .parametric, bypass: false
        ),
        EQBandConfiguration(
            frequency: 9000, q: 0.9, gain: 1.5,
            filterType: .highShelf, bypass: false
        ),
    ]

    /// The channel layer's band list: the treatment's bands first,
    /// the clarity set appended when dialogue is on for the channel.
    static func composedBands(treatmentBands: [EQBandConfiguration], dialogueEnabled: Bool) -> [EQBandConfiguration] {
        dialogueEnabled ? treatmentBands + bands : treatmentBands
    }
}
