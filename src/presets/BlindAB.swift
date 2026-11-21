// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// C2: the blind A/B state machine — which side holds the
/// candidate, which sides have been heard, and what a pick means.
/// Nothing about audio lives here; the controller drives the
/// store, this type keeps the test honest: labels stay hidden,
/// a pick is impossible until both sides have played, and the
/// reveal maps the picked letter back to candidate-or-current.
enum BlindABSession {
    enum Letter: Equatable {
        case a, b
    }

    enum Phase: Equatable {
        case listening
        case revealed(winnerIsCandidate: Bool)
    }

    struct State: Equatable {
        let candidateIsA: Bool
        private(set) var heardA: Bool
        private(set) var heardB: Bool
        private(set) var current: Letter
        private(set) var phase: Phase

        init(candidateIsA: Bool) {
            self.candidateIsA = candidateIsA
            self.current = .a
            self.heardA = true
            self.heardB = false
            self.phase = .listening
        }

        var canPick: Bool {
            phase == .listening && heardA && heardB
        }

        func isCandidate(_ letter: Letter) -> Bool {
            (letter == .a) == candidateIsA
        }

        mutating func show(_ letter: Letter) {
            guard phase == .listening else { return }
            current = letter
            if letter == .a { heardA = true } else { heardB = true }
        }

        mutating func pick(_ letter: Letter) {
            guard canPick else { return }
            phase = .revealed(winnerIsCandidate: isCandidate(letter))
        }
    }
}
