// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// B1: the tap deafness rule (all three facts necessary), and the
/// new default route.
final class TapDeafnessTests: XCTestCase {
    func testDeafWhenAliveSilentAndOthersPlaying() {
        XCTAssertTrue(TapDeafness.isDeaf(
            framesAdvanced: true,
            inputSamplesDB: [-90, -90],
            otherAppProducingOutput: true
        ))
    }

    func testNotDeafWhenAnySampleBreaksTheFloor() {
        XCTAssertFalse(TapDeafness.isDeaf(
            framesAdvanced: true,
            inputSamplesDB: [-90, -63],
            otherAppProducingOutput: true
        ))
    }

    func testNotDeafWhenNothingElseIsPlaying() {
        // Silence everywhere is the truth, not a symptom.
        XCTAssertFalse(TapDeafness.isDeaf(
            framesAdvanced: true,
            inputSamplesDB: [-90, -90],
            otherAppProducingOutput: false
        ))
    }

    func testNotDeafWhenFramesNeverAdvanced() {
        // That's the ordinary dead route — the frame watchdog's
        // territory, not this rule's.
        XCTAssertFalse(TapDeafness.isDeaf(
            framesAdvanced: false,
            inputSamplesDB: [-90, -90],
            otherAppProducingOutput: true
        ))
    }

    func testNotDeafWithoutSamples() {
        XCTAssertFalse(TapDeafness.isDeaf(
            framesAdvanced: true,
            inputSamplesDB: [],
            otherAppProducingOutput: true
        ))
    }

    func testDefaultCaptureModeIsTheTap() {
        XCTAssertEqual(
            AppStateSnapshot.default.captureMode,
            CaptureMode.processTap.rawValue,
            "A fresh user's front door is the driverless route (B1)"
        )
    }

    /// 11-21 regression: silent helpers count as "playing", so a granted tap hearing
    /// silence at launch must never be called deaf (that left app sliders dead).
    func testGrantedCaptureIsNeverDeaf() {
        XCTAssertFalse(TapDeafness.isDeaf(framesAdvanced: true, inputSamplesDB: [-120, -120],
                                          otherAppProducingOutput: true, captureGranted: true))
        XCTAssertTrue(TapDeafness.isDeaf(framesAdvanced: true, inputSamplesDB: [-120, -120],
                                         otherAppProducingOutput: true, captureGranted: false))
    }
}
