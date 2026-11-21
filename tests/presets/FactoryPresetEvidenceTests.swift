// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// The 2026-11 factory library is built from listener-preference evidence
/// under a stated grammar (see FactoryPresets.swift). These tests hold the
/// library to that grammar so a future preset cannot quietly break it:
/// axis/function names only, broad low-Q shaping, preamp covering the
/// largest boost, and no positive band outside the audible working range.
final class FactoryPresetEvidenceTests: XCTestCase {

    private var shapingBands: [PresetBand] {
        FactoryPresets.all.flatMap { $0.settings.leftBands }.filter { $0.gain != 0 }
    }

    func testLibraryHasTheFifteenEvidencePresets() {
        let names = FactoryPresets.all.map { $0.metadata.name }
        XCTAssertEqual(names, [
            "Flat", "Reference — Speakers", "Reference — Headphones",
            "Bass −", "Bass +", "Bass ++", "De-Boom", "Bright", "Soft",
            "Lyric Clarity", "Warmth", "Loudness — Low Volume", "Night",
            "Small Speakers", "Spoken Word",
        ])
        XCTAssertEqual(Set(names).count, names.count, "preset names must be unique")
    }

    func testNoGenreNamesSurvive() {
        let retired = ["Bass Boost", "Treble Boost", "Vocal Presence", "Loudness",
                       "Acoustic", "Rock", "Electronic", "Jazz", "Podcast", "Classical"]
        for name in retired {
            XCTAssertFalse(FactoryPresets.all.contains { $0.metadata.name == name },
                           "\(name) must stay retired")
        }
    }

    func testPreampCoversTheLargestBoost() {
        for preset in FactoryPresets.all {
            let maxGain = preset.settings.leftBands.map(\.gain).max() ?? 0
            if maxGain > 0 {
                XCTAssertLessThanOrEqual(
                    preset.settings.inputGain, -maxGain + 0.001,
                    "\(preset.metadata.name): preamp \(preset.settings.inputGain) does not cover its +\(maxGain) dB band")
            } else {
                XCTAssertEqual(preset.settings.inputGain, 0,
                               "\(preset.metadata.name): no boost, so no preamp cut")
            }
        }
    }

    func testShapingStaysBroadAndInRange() {
        for band in shapingBands {
            XCTAssertLessThanOrEqual(band.q, 2.0,
                                     "taste presets never use narrow bands (found Q \(band.q) at \(band.frequency) Hz)")
            XCTAssertLessThanOrEqual(abs(band.gain), 8.0,
                                     "no factory band beyond ±8 dB (found \(band.gain) dB at \(band.frequency) Hz)")
            if band.gain > 0 {
                XCTAssertGreaterThanOrEqual(band.frequency, 50,
                                            "no positive band below 50 Hz (found \(band.frequency) Hz)")
                XCTAssertLessThanOrEqual(band.frequency, 16000,
                                         "no positive band above 16 kHz (found \(band.frequency) Hz)")
            }
        }
    }

    func testPresetsKeepAFullBandLayout() {
        for preset in FactoryPresets.all {
            XCTAssertGreaterThanOrEqual(preset.settings.leftBands.count, 10,
                                        "\(preset.metadata.name) collapses the band grid")
            XCTAssertEqual(preset.settings.leftBands.count, preset.settings.rightBands.count)
        }
    }

    func testReferenceSpeakersMatchesTheStudyValues() {
        let preset = FactoryPresets.referenceSpeakers
        let bands = preset.settings.leftBands.filter { $0.gain != 0 }
        XCTAssertEqual(bands.count, 2)
        XCTAssertTrue(bands.contains { $0.filterType == .lowShelf && $0.frequency == 105 && $0.gain == 6.6 && $0.q == 0.70 })
        XCTAssertTrue(bands.contains { $0.filterType == .highShelf && $0.frequency == 2500 && $0.gain == -2.4 && $0.q == 0.70 })
        XCTAssertEqual(preset.settings.inputGain, -6.6)
    }
}
