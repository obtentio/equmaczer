import XCTest
@testable import equmaczer

final class AudiogramTests: XCTestCase {
    func testNormalThresholdsComposeNothing() {
        var audiogram = Audiogram()
        for index in Audiogram.frequencies.indices { audiogram.setThreshold(15, ear: .left, index: index) }
        XCTAssertTrue(audiogram.bands(for: .left).isEmpty)
    }

    func testThresholdBecomesPerEarBellAtItsFrequency() {
        var audiogram = Audiogram()
        audiogram.setThreshold(35, ear: .left, index: 4)   // 4 kHz: (35-15)*0.5 = 10 dB
        audiogram.setThreshold(55, ear: .right, index: 5)  // 8 kHz: 20 → capped at 12 dB
        let left = audiogram.bands(for: .left)
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(left[0].frequency, 4000)
        XCTAssertEqual(left[0].gain, 10, accuracy: 0.001)
        XCTAssertEqual(left[0].filterType, .parametric)
        let right = audiogram.bands(for: .right)
        XCTAssertEqual(right.count, 1)
        XCTAssertEqual(right[0].frequency, 8000)
        XCTAssertEqual(right[0].gain, HearingState.rangeDB.upperBound, accuracy: 0.001)
    }

    func testThresholdsClampToEntryRange() {
        var audiogram = Audiogram()
        audiogram.setThreshold(500, ear: .left, index: 0)
        audiogram.setThreshold(-500, ear: .right, index: 0)
        audiogram.setThreshold(40, ear: .left, index: 99)
        XCTAssertEqual(audiogram.leftDB[0], Audiogram.rangeDB.upperBound)
        XCTAssertEqual(audiogram.rightDB[0], Audiogram.rangeDB.lowerBound)
    }

    func testStateUsesAudiogramPerEarThroughLayerComposition() {
        var state = HearingState()
        state.enabled = true
        state.leftLowDB = 6   // by-ear shelf, ignored once the audiogram is in use
        var audiogram = Audiogram()
        audiogram.setThreshold(45, ear: .right, index: 3)  // 2 kHz → 12 dB (cap 15)
        state.audiogram = audiogram
        XCTAssertTrue(state.usesAudiogram)
        XCTAssertEqual(state.sourceLabel, "audiogram, R")
        XCTAssertTrue(HearingComposition.leftBands(for: state).isEmpty, "Left ear entered nothing: no by-ear shelf leaks in")
        let right = HearingComposition.rightBands(for: state)
        XCTAssertEqual(right.map(\.frequency), [2000])
    }

    func testSourceLabelsAndFallbackToByEar() {
        var state = HearingState()
        XCTAssertEqual(state.sourceLabel, "by-ear test")
        var audiogram = Audiogram()
        audiogram.setThreshold(30, ear: .left, index: 0)
        audiogram.setThreshold(30, ear: .right, index: 0)
        state.audiogram = audiogram
        XCTAssertEqual(state.sourceLabel, "audiogram, L/R")
        state.audiogram?.inUse = false
        XCTAssertEqual(state.sourceLabel, "by-ear test")
        state.leftLowDB = 4
        state.enabled = true
        XCTAssertEqual(HearingComposition.leftBands(for: state).first?.filterType, .lowShelf)
    }

    func testOlderSavedStateWithoutAudiogramStillDecodes() throws {
        let json = #"{"enabled":true,"leftLowDB":1,"leftHighDB":2,"rightLowDB":3,"rightHighDB":4}"#
        let state = try JSONDecoder().decode(HearingState.self, from: Data(json.utf8))
        XCTAssertNil(state.audiogram)
        XCTAssertEqual(state.rightHighDB, 4)
    }

    func testAudiogramRoundTripsThroughStore() {
        let defaults = UserDefaults(suiteName: "equmaczer.audiogram.\(UUID())")!
        let store = HearingStore(defaults: defaults)
        var state = HearingState()
        state.audiogram = Audiogram()
        state.audiogram?.setThreshold(40, ear: .left, index: 2)
        store.save(state)
        XCTAssertEqual(store.load().audiogram?.leftDB[2], 40)
    }
}
