// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import AVFoundation
import Foundation

/// Factory presets that ship with the app.
///
/// The library was rebuilt in 2026-11 from listener-preference research
/// (Harman/Olive controlled studies; full evidence review in the project
/// notes, "equmaczer presets — the evidence"). Its grammar:
///
/// - Names state an axis or a verified function, never a music genre.
///   Controlled tests found programme material does not significantly move
///   listeners' preferred bass/treble settings, and a genre's spectral
///   balance is already in its master — a genre preset double-counts it.
/// - Shelves are canonical: low shelf 105 Hz Q 0.70, high shelf 10 kHz
///   Q 0.71. Peaking bands stay broad (Q ≤ 1.0 here; never above 2 in a
///   taste preset — narrow peaks are the most audible artefact per dB).
/// - Sibling steps are 3–4 dB in the bass, 2–3 dB in treble/presence,
///   above the ~1 dB audibility floor for broad changes.
/// - Preamp (inputGain) is minus the largest positive band gain, so a
///   preset never adds net level on its own; the auto-preamp covers the
///   composite curve on top.
/// - "Night" is the EQ half of quiet listening (less bass for neighbours,
///   a little presence for low-level clarity). True night modes also
///   compress dynamics; equmaczer has no dynamics stage yet, so this
///   preset does not claim to be one.
enum FactoryPresets {
    /// All factory presets.
    static let all: [Preset] = [
        flat,
        referenceSpeakers,
        referenceHeadphones,
        bassMinus,
        bassPlus,
        bassPlusPlus,
        deBoom,
        bright,
        soft,
        lyricClarity,
        warmth,
        loudnessLowVolume,
        night,
        smallSpeakers,
        spokenWord,
    ]

    /// Flat - neutral EQ with all bands at 0 dB.
    static let flat: Preset = {
        let bands = defaultBands(count: 10, gainAdjustments: [:])
        return Preset(
            metadata: PresetMetadata(name: "Flat", isFactoryPreset: true),
            settings: PresetSettings(
                inputGain: 0,
                outputGain: 0,
                leftBands: bands,
                rightBands: bands
            )
        )
    }()

    /// Reference — Speakers: what listeners chose from a flat in-room
    /// system (Olive/Welti/McMullin, AES 135, 2013): +6.6 dB below 105 Hz,
    /// −2.4 dB above 2.5 kHz.
    static let referenceSpeakers = shaped(
        name: "Reference — Speakers", preamp: -6.6,
        shaping: [
            band(105, .lowShelf, 6.6, 0.70),
            band(2500, .highShelf, -2.4, 0.70),
        ])

    /// Reference — Headphones: the loudspeaker preference with ~2 dB less
    /// at the bass end and flat treble (same 2013 study programme).
    static let referenceHeadphones = shaped(
        name: "Reference — Headphones", preamp: -4.5,
        shaping: [
            band(105, .lowShelf, 4.5, 0.70),
        ])

    /// Bass −: the −2 to −3 dB listener segment (Olive segmentation,
    /// AES 146, 2019).
    static let bassMinus = shaped(
        name: "Bass −", preamp: 0,
        shaping: [
            band(105, .lowShelf, -3.0, 0.70),
        ])

    /// Bass +: one taste step up; the +4–6 dB segment delta.
    static let bassPlus = shaped(
        name: "Bass +", preamp: -4.0,
        shaping: [
            band(105, .lowShelf, 4.0, 0.70),
        ])

    /// Bass ++: the largest legitimate step — Dirac's +8 Harman file,
    /// still below the untrained-listener mean preference (+11.2 dB).
    static let bassPlusPlus = shaped(
        name: "Bass ++", preamp: -8.0,
        shaping: [
            band(105, .lowShelf, 8.0, 0.70),
        ])

    /// De-Boom: boomy rooms and corner-loaded desktop speakers.
    static let deBoom = shaped(
        name: "De-Boom", preamp: 0,
        shaping: [
            band(105, .lowShelf, -4.0, 0.70),
            band(250, .parametric, -2.0, 1.00),
        ])

    /// Bright: one treble step. Demographic treble deltas in the
    /// preference data are only +2–3 dB, so there is no Bright ++.
    static let bright = shaped(
        name: "Bright", preamp: -3.0,
        shaping: [
            band(10000, .highShelf, 3.0, 0.71),
        ])

    /// Soft: the inverse step, for bright/harsh systems and long sessions.
    static let soft = shaped(
        name: "Soft", preamp: 0,
        shaping: [
            band(10000, .highShelf, -3.0, 0.71),
        ])

    /// Lyric Clarity: presence lift in the 2–5 kHz intelligibility region
    /// with a low-mid mud cut.
    static let lyricClarity = shaped(
        name: "Lyric Clarity", preamp: -2.5,
        shaping: [
            band(300, .parametric, -1.5, 0.90),
            band(3000, .parametric, 2.5, 1.00),
        ])

    /// Warmth: low-mid body with a small presence dip (Fazenda's
    /// operationalisation: boost 200–500 Hz, dip 2–6 kHz).
    static let warmth = shaped(
        name: "Warmth", preamp: -2.5,
        shaping: [
            band(250, .parametric, 2.5, 0.90),
            band(3500, .parametric, -1.5, 1.00),
        ])

    /// Loudness — Low Volume: roughly half of full ISO 226 compensation,
    /// labelled with its assumption (listening around 50–60 phon). For
    /// level-tracking compensation, the ISO 226 feature in the correction
    /// panel follows the actual output volume instead.
    static let loudnessLowVolume = shaped(
        name: "Loudness — Low Volume", preamp: -6.0,
        shaping: [
            band(100, .lowShelf, 6.0, 0.70),
            band(12000, .highShelf, 2.5, 0.71),
        ])

    /// Night: the EQ half of quiet listening (see the note at the top of
    /// this file — no dynamics stage yet).
    static let night = shaped(
        name: "Night", preamp: -1.5,
        shaping: [
            band(105, .lowShelf, -3.0, 0.70),
            band(3000, .parametric, 1.5, 1.00),
            band(10000, .highShelf, -2.0, 0.71),
        ])

    /// Small Speakers: shed sub-bass a small driver cannot reproduce
    /// (boosting below rolloff only overdrives it), lift the upper bass
    /// it can, add presence for nearfield clarity. The shape Apple and
    /// Spotify ship under the same name.
    static let smallSpeakers = shaped(
        name: "Small Speakers", preamp: -3.0,
        shaping: [
            band(60, .lowShelf, -5.0, 0.70),
            band(180, .parametric, 3.0, 0.90),
            band(3500, .parametric, 2.0, 1.00),
        ])

    /// Spoken Word: rumble/boom removal plus the speech-intelligibility
    /// band, kept broad (Q 1) because narrow peaks harm intelligibility
    /// more than dips (Bücklein, 1981).
    static let spokenWord = shaped(
        name: "Spoken Word", preamp: -3.0,
        shaping: [
            band(100, .lowShelf, -4.0, 0.70),
            band(3000, .parametric, 3.0, 1.00),
        ])

    // MARK: - Helpers

    /// One shaping band of a preset.
    private static func band(_ frequency: Float, _ type: FilterType, _ gain: Float, _ q: Float) -> PresetBand {
        PresetBand(frequency: frequency, q: q, gain: gain, filterType: type, bypass: false)
    }

    /// Builds a preset from its shaping bands: the shaping bands are placed
    /// exactly as specified, and the remaining slots of the standard
    /// 10-band grid are filled at 0 dB (skipping any grid frequency within
    /// a third of an octave of a shaping band), so selecting a preset
    /// keeps a full band layout to keep editing from.
    private static func shaped(name: String, preamp: Float, shaping: [PresetBand]) -> Preset {
        var bands = shaping
        for frequency in EQConfiguration.frequenciesForBandCount(10) {
            let collides = shaping.contains {
                abs(log2(Double($0.frequency / frequency))) <= 0.33
            }
            if !collides {
                bands.append(PresetBand(
                    frequency: frequency,
                    q: EQConfiguration.defaultQ,
                    gain: 0,
                    filterType: .parametric,
                    bypass: false
                ))
            }
        }
        bands.sort { $0.frequency < $1.frequency }
        return Preset(
            metadata: PresetMetadata(name: name, isFactoryPreset: true),
            settings: PresetSettings(
                inputGain: preamp,
                outputGain: 0,
                leftBands: bands,
                rightBands: bands
            )
        )
    }

    /// Generates default bands with optional gain adjustments.
    private static func defaultBands(count: Int, gainAdjustments: [Int: Float]) -> [PresetBand] {
        let frequencies = EQConfiguration.frequenciesForBandCount(count)
        return frequencies.enumerated().map { index, frequency in
            PresetBand(
                frequency: frequency,
                q: EQConfiguration.defaultQ,
                gain: gainAdjustments[index] ?? 0,
                filterType: .parametric,
                bypass: false
            )
        }
    }
}

// MARK: - PresetManager Extension

extension PresetManager {
    private static let factoryPresetVersion = 11  // Bump when factory presets change (v2 format)
    private static let factoryVersionKey = "equalizer.factoryPresetVersion"

    /// Factory preset names retired by the current library. On a version
    /// bump, stored presets carrying the factory flag under one of these
    /// names are removed (the genre library of versions ≤ 10); user
    /// presets are never touched — the flag is what marks a preset as
    /// factory-owned, the same assumption the replacement path makes.
    private static let retiredFactoryPresetNames: Set<String> = [
        "Bass Boost", "Treble Boost", "Vocal Presence", "Loudness",
        "Acoustic", "Rock", "Electronic", "Jazz", "Podcast", "Classical",
    ]

    /// Installs factory presets if they don't exist or version changed.
    func installFactoryPresetsIfNeeded() {
        let currentVersion = UserDefaults.standard.integer(forKey: Self.factoryVersionKey)
        let needsReinstall = currentVersion < Self.factoryPresetVersion

        if needsReinstall {
            for stored in presets where stored.metadata.isFactoryPreset
                && Self.retiredFactoryPresetNames.contains(stored.metadata.name) {
                try? deletePreset(named: stored.metadata.name)
            }
        }

        for factoryPreset in FactoryPresets.all {
            let existingIndex = presets.firstIndex(where: { $0.metadata.name == factoryPreset.metadata.name })

            if needsReinstall {
                if let index = existingIndex {
                    let existingPreset = presets[index]
                    if existingPreset.metadata.isFactoryPreset {
                        // Pristine factory preset - safe to replace with updated version
                        try? savePresetWithoutReload(factoryPreset)
                    }
                    // else: user-modified preset, skip to preserve changes
                } else {
                    // New factory preset (added in this version), install it
                    try? savePresetWithoutReload(factoryPreset)
                }
            }
            // When !needsReinstall: do nothing - preserve user's presets
        }

        if needsReinstall {
            UserDefaults.standard.set(Self.factoryPresetVersion, forKey: Self.factoryVersionKey)
        }

        // Reload once after all factory presets are saved
        loadAllPresets()
    }
}
