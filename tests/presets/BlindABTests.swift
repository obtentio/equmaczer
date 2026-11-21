// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// C2: the blind test's honesty rules — both sides heard before
/// a pick, the picked letter mapping to the right sound, and the
/// level-match trim staying a trim (±6 dB, inside the input gain).
final class BlindABTests: XCTestCase {
    func testPickImpossibleUntilBothSidesHeard() {
        var state = BlindABSession.State(candidateIsA: true)
        XCTAssertFalse(state.canPick)
        state.pick(.a)
        XCTAssertEqual(state.phase, .listening, "an early pick must do nothing")
        state.show(.b)
        XCTAssertTrue(state.canPick)
    }

    func testPickMapsLetterToCandidateWhenCandidateIsA() {
        var state = BlindABSession.State(candidateIsA: true)
        state.show(.b)
        state.pick(.a)
        XCTAssertEqual(state.phase, .revealed(winnerIsCandidate: true))
    }

    func testPickMapsLetterToCandidateWhenCandidateIsB() {
        var state = BlindABSession.State(candidateIsA: false)
        state.show(.b)
        state.pick(.a)
        XCTAssertEqual(state.phase, .revealed(winnerIsCandidate: false))
        var other = BlindABSession.State(candidateIsA: false)
        other.show(.b)
        other.pick(.b)
        XCTAssertEqual(other.phase, .revealed(winnerIsCandidate: true))
    }

    func testShowingAfterRevealDoesNothing() {
        var state = BlindABSession.State(candidateIsA: true)
        state.show(.b)
        state.pick(.b)
        let current = state.current
        state.show(.a)
        XCTAssertEqual(state.current, current)
    }

    @MainActor
    func testBlindTrimClampsAndComposes() {
        let config = EQConfiguration()
        XCTAssertEqual(config.effectiveInputGainDB, config.inputGain, accuracy: 0.001)
        config.setBlindTrimDB(20)
        XCTAssertEqual(config.blindTrimDB, 6, accuracy: 0.001)
        XCTAssertEqual(config.effectiveInputGainDB, config.inputGain + 6, accuracy: 0.001)
        config.setBlindTrimDB(-20)
        XCTAssertEqual(config.blindTrimDB, -6, accuracy: 0.001)
        config.setBlindTrimDB(0)
        XCTAssertEqual(config.blindTrimDB, 0, accuracy: 0.001)
    }
}
