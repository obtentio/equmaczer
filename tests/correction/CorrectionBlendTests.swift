// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// C3: the blend scales the correction's own bands — and only
/// those. Trims are the listener's absolute additions and the
/// loudness shelves are a separate feature; neither scales.
final class CorrectionBlendTests: XCTestCase {
    private func profile(blend: Double?) -> DeviceCorrectionProfile {
        var profile = DeviceCorrectionProfile(
            deviceUID: "uid", deviceName: "Test Phones", sourceName: "AutoEq: test",
            preampDB: -4, bands: [
                PresetBand(frequency: 250, q: 1.5, gain: 6, filterType: .parametric, bypass: false),
                PresetBand(frequency: 3_000, q: 2, gain: -3, filterType: .parametric, bypass: false),
            ]
        )
        profile.bassTrimDB = 2
        profile.blendPercent = blend
        return profile
    }

    private func composed(_ profile: DeviceCorrectionProfile) -> [EQBandConfiguration] {
        CorrectionComposer.composeBands(
            profile: profile, loudnessEnabled: false, volumeScalar: nil, loudnessStrength: 1
        )
    }

    func testBlendHalvesProfileGainsButNotTrims() {
        let bands = composed(profile(blend: 50))
        XCTAssertEqual(bands.count, 3, "two profile bands + the bass trim shelf")
        XCTAssertEqual(bands[0].gain, 3, accuracy: 0.01)
        XCTAssertEqual(bands[1].gain, -1.5, accuracy: 0.01)
        let trim = bands.first { $0.filterType == .lowShelf }
        XCTAssertEqual(trim?.gain ?? 0, 2, accuracy: 0.01, "the listener's trim is absolute")
    }

    func testBlendFullIsIdentityAndZeroSilencesTheCorrection() {
        let full = composed(profile(blend: 100))
        XCTAssertEqual(full[0].gain, 6, accuracy: 0.01)
        let none = composed(profile(blend: nil))
        XCTAssertEqual(none[0].gain, 6, accuracy: 0.01, "an unset blend is 100%")
        let zero = composed(profile(blend: 0))
        XCTAssertEqual(zero[0].gain, 0, accuracy: 0.01)
        XCTAssertEqual(zero[1].gain, 0, accuracy: 0.01)
    }

    func testProfileWithoutBlendFieldDecodesAsFull() throws {
        let json = """
        {"deviceUID":"u","deviceName":"n","sourceName":"s","preampDB":-2,
         "bands":[],"bassTrimDB":0,"trebleTrimDB":0}
        """
        let decoded = try JSONDecoder().decode(DeviceCorrectionProfile.self, from: Data(json.utf8))
        XCTAssertNil(decoded.blendPercent)
        XCTAssertEqual(decoded.blendFactor, 1, accuracy: 0.001)
    }

    func testBlendFactorClamps() {
        XCTAssertEqual(profile(blend: 70).blendFactor, 0.7, accuracy: 0.001)
        XCTAssertEqual(profile(blend: 140).blendFactor, 1, accuracy: 0.001)
        XCTAssertEqual(profile(blend: -5).blendFactor, 0, accuracy: 0.001)
    }
}
