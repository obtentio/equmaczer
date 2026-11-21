// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// Tier 2 measurement tests: ISO 226 contour anchors computed from the
/// standard's own formula and Table 1 (cross-checked in Python),
/// compensation behaviour, the AutoEq importer, the profile store,
/// and correction-layer composition.
final class LoudnessCompensationTests: XCTestCase {

    // MARK: - Contour anchors (ISO 226:2003, Equation 1 + Table 1)

    func testSPLAt1kHzEqualsPhonByDefinition() {
        for phon in [20.0, 40.0, 60.0, 80.0] {
            XCTAssertEqual(
                LoudnessCompensation.spl(phons: phon, frequency: 1000),
                phon, accuracy: 0.05,
                "At 1 kHz the contour SPL must equal the loudness level"
            )
        }
    }

    func testSPLAnchorsMatchTheStandard() {
        // Computed from Equation (1) with Table 1 parameters.
        XCTAssertEqual(LoudnessCompensation.spl(phons: 40, frequency: 100), 64.4, accuracy: 0.2)
        XCTAssertEqual(LoudnessCompensation.spl(phons: 60, frequency: 20), 109.5, accuracy: 0.3)
        XCTAssertEqual(LoudnessCompensation.spl(phons: 80, frequency: 4000), 78.3, accuracy: 0.2)
    }

    // MARK: - Compensation

    func testCompensationIsZeroAtReference() {
        let gains = LoudnessCompensation.compensation(phons: 80, strength: 1.0)
        XCTAssertEqual(gains.lowDB, 0, accuracy: 0.001)
        XCTAssertEqual(gains.highDB, 0, accuracy: 0.001)
    }

    func testCompensationAt40Phon() {
        let gains = LoudnessCompensation.compensation(phons: 40, strength: 1.0)
        XCTAssertEqual(gains.lowDB, 11.89, accuracy: 0.15)
        XCTAssertEqual(gains.highDB, 2.55, accuracy: 0.15)
    }

    func testCompensationScalesWithStrengthAndFallsWithLevel() {
        let full = LoudnessCompensation.compensation(phons: 40, strength: 1.0)
        let half = LoudnessCompensation.compensation(phons: 40, strength: 0.5)
        XCTAssertEqual(half.lowDB, full.lowDB / 2, accuracy: 0.01)

        let at30 = LoudnessCompensation.compensation(phons: 30, strength: 1.0)
        let at60 = LoudnessCompensation.compensation(phons: 60, strength: 1.0)
        XCTAssertGreaterThan(at30.lowDB, full.lowDB)
        XCTAssertGreaterThan(full.lowDB, at60.lowDB)
        XCTAssertGreaterThan(at60.lowDB, 0)
        XCTAssertLessThanOrEqual(at30.lowDB, LoudnessCompensation.maxLowBoostDB)
    }

    func testEstimatedPhonMapping() {
        XCTAssertEqual(LoudnessCompensation.estimatedPhon(volumeScalar: 1.0), 85, accuracy: 0.01)
        XCTAssertEqual(LoudnessCompensation.estimatedPhon(volumeScalar: 0.1), 65, accuracy: 0.01)
        XCTAssertEqual(LoudnessCompensation.estimatedPhon(volumeScalar: 0), 25, accuracy: 0.01)
    }
}

final class AutoEqImporterTests: XCTestCase {
    private let sampleText = """
    Preamp: -6.4 dB
    Filter 1: ON PK Fc 1957 Hz Gain -2.9 dB Q 1.41
    Filter 2: ON LSC Fc 105 Hz Gain 4.3 dB Q 0.71
    Filter 3: OFF PK Fc 8000 Hz Gain 3.0 dB Q 2.00
    Filter 4: ON HSC Fc 10000 Hz Gain -1.5 dB Q 0.71
    """

    func testParsesPreampBandsAndShelfTypes() throws {
        let result = try AutoEqImporter.parseProfile(
            text: sampleText,
            deviceUID: "uid-1",
            deviceName: "Test Headphones",
            sourceName: "AutoEq: test"
        )
        let profile = result.profile
        XCTAssertEqual(profile.preampDB, -6.4, accuracy: 0.001)
        XCTAssertEqual(profile.bands.count, 4)
        XCTAssertEqual(profile.bands[0].filterType, .parametric)
        XCTAssertEqual(profile.bands[0].frequency, 1957, accuracy: 0.5)
        XCTAssertEqual(profile.bands[0].gain, -2.9, accuracy: 0.001)
        XCTAssertEqual(profile.bands[1].filterType, .lowShelf)
        XCTAssertTrue(profile.bands[2].bypass, "OFF filters stay in the profile, bypassed")
        XCTAssertEqual(profile.bands[3].filterType, .highShelf)
        XCTAssertEqual(profile.deviceUID, "uid-1")
    }

    func testRejectsTextWithoutFilters() {
        XCTAssertThrowsError(
            try AutoEqImporter.parseProfile(
                text: "Preamp: -3.0 dB\nNo filters here.",
                deviceUID: "uid-1",
                deviceName: "Test",
                sourceName: "AutoEq: empty"
            )
        )
    }
}

final class DeviceCorrectionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.correction.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testSaveLoadRemoveRoundTrip() {
        let store = DeviceCorrectionStore(defaults: defaults)
        XCTAssertNil(store.profile(forUID: "uid-9"))

        let profile = DeviceCorrectionProfile(
            deviceUID: "uid-9",
            deviceName: "Headphones",
            sourceName: "AutoEq: x",
            preampDB: -3.5,
            bands: [PresetBand(frequency: 100, q: 1.0, gain: -2, filterType: .parametric, bypass: false)],
            bassTrimDB: 1.5,
            trebleTrimDB: -0.5
        )
        store.save(profile)

        let loaded = store.profile(forUID: "uid-9")
        XCTAssertEqual(loaded?.sourceName, "AutoEq: x")
        XCTAssertEqual(loaded?.preampDB, -3.5)
        XCTAssertEqual(loaded?.bands.count, 1)
        XCTAssertEqual(loaded?.bassTrimDB, 1.5)

        store.remove(forUID: "uid-9")
        XCTAssertNil(store.profile(forUID: "uid-9"))
    }
}

final class CorrectionComposerTests: XCTestCase {
    private func makeProfile(bassTrim: Float = 0, trebleTrim: Float = 0) -> DeviceCorrectionProfile {
        DeviceCorrectionProfile(
            deviceUID: "uid-1",
            deviceName: "Headphones",
            sourceName: "AutoEq: x",
            preampDB: -4,
            bands: [
                PresetBand(frequency: 2000, q: 1.41, gain: -3, filterType: .parametric, bypass: false),
                PresetBand(frequency: 6000, q: 2.0, gain: 2, filterType: .parametric, bypass: true),
            ],
            bassTrimDB: bassTrim,
            trebleTrimDB: trebleTrim
        )
    }

    func testLoudnessOnlyAtFullVolumeComposesNothing() {
        // Full volume estimates 85 phon — above the 80 phon reference.
        let bands = CorrectionComposer.composeBands(
            profile: nil, loudnessEnabled: true, volumeScalar: 1.0, loudnessStrength: 1.0
        )
        XCTAssertTrue(bands.isEmpty)
    }

    func testLoudnessShelvesAtLowVolume() {
        // Volume 0.1 → 65 phon → ≈ +4.7 dB low shelf, +1.1 dB high shelf.
        let bands = CorrectionComposer.composeBands(
            profile: nil, loudnessEnabled: true, volumeScalar: 0.1, loudnessStrength: 1.0
        )
        XCTAssertEqual(bands.count, 2)
        XCTAssertEqual(bands[0].filterType, .lowShelf)
        XCTAssertEqual(bands[0].gain, 4.66, accuracy: 0.2)
        XCTAssertEqual(bands[1].filterType, .highShelf)
        XCTAssertEqual(bands[1].gain, 1.08, accuracy: 0.2)
    }

    func testProfileBandsAndTrimsComposeInOrder() {
        let bands = CorrectionComposer.composeBands(
            profile: makeProfile(bassTrim: -3, trebleTrim: 1.5),
            loudnessEnabled: false, volumeScalar: nil, loudnessStrength: 0.5
        )
        XCTAssertEqual(bands.count, 4, "2 profile bands + 2 trims, no loudness")
        XCTAssertEqual(bands[0].frequency, 2000)
        XCTAssertTrue(bands[1].bypass, "Profile bypass flags carry through")
        XCTAssertEqual(bands[2].filterType, .lowShelf)
        XCTAssertEqual(bands[2].gain, -3, accuracy: 0.001)
        XCTAssertEqual(bands[3].filterType, .highShelf)
        XCTAssertEqual(bands[3].gain, 1.5, accuracy: 0.001)
    }

    func testTrimsNeedAProfile() {
        let bands = CorrectionComposer.composeBands(
            profile: nil, loudnessEnabled: false, volumeScalar: nil, loudnessStrength: 0.5
        )
        XCTAssertTrue(bands.isEmpty)
    }

    func testBassTrimAtPreferenceRangeTopComposesFullShelf() {
        // A2: bass runs to +12 (Olive's middle 90% tops at +12.6 dB);
        // the full value must reach the composed shelf unclamped.
        let bands = CorrectionComposer.composeBands(
            profile: makeProfile(bassTrim: 12),
            loudnessEnabled: false, volumeScalar: nil, loudnessStrength: 0.5
        )
        XCTAssertEqual(bands.count, 3, "2 profile bands + bass shelf (treble is 0)")
        XCTAssertEqual(bands[2].filterType, .lowShelf)
        XCTAssertEqual(bands[2].frequency, 105)
        XCTAssertEqual(bands[2].gain, 12, accuracy: 0.001)
    }

    func testTrebleTrimAtRangeBottomComposesFullShelf() {
        let bands = CorrectionComposer.composeBands(
            profile: makeProfile(trebleTrim: -10),
            loudnessEnabled: false, volumeScalar: nil, loudnessStrength: 0.5
        )
        XCTAssertEqual(bands.count, 3, "2 profile bands + treble shelf (bass is 0)")
        XCTAssertEqual(bands[2].filterType, .highShelf)
        XCTAssertEqual(bands[2].frequency, 10_000)
        XCTAssertEqual(bands[2].gain, -10, accuracy: 0.001)
    }
}
