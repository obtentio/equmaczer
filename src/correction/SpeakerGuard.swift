// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// D6: the speaker guard profile — a generic correction for
/// small built-in speakers, built from the physics of the
/// problem rather than a measurement: deep lows a small driver
/// cannot reproduce only distort and eat excursion, and the
/// boom region above them is where small enclosures exaggerate.
/// Two cuts, nothing boosted, preamp zero — a guard that
/// boosted would contradict itself. Its source details say
/// plainly that it is a generic shape, not a model measurement
/// (the A5 law: no invented precision).
enum SpeakerGuard {
    static let sourceName = "Speaker guard"
    static let sourceDetails = "A generic guard for small built-in speakers — not a measurement of this model. It removes the low content small drivers cannot reproduce (which only distorts and eats headroom) and tames the boom region. Tune or remove it like any correction."

    static func importResult(deviceUID: String, deviceName: String) -> AutoEqImportResult {
        let bands: [PresetBand] = [
            PresetBand(frequency: 100, q: 0.707, gain: 0, filterType: .highPass, bypass: false),
            PresetBand(frequency: 220, q: 0.7, gain: -2.5, filterType: .lowShelf, bypass: false),
        ]
        let profile = DeviceCorrectionProfile(
            deviceUID: deviceUID,
            deviceName: deviceName,
            sourceName: sourceName,
            sourceDetails: sourceDetails,
            preampDB: 0,
            bands: bands
        )
        return AutoEqImportResult(profile: profile, warnings: [])
    }
}
