// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// The timing heart of auto-pause (A8), pure and deterministic:
/// pause only once the stage has *held*, restore only once it has
/// been clear a while longer. The asymmetry is the feature —
/// flapping (pause/resume/pause on a blipping trigger) is the
/// failure mode that gets features like this switched off forever.
struct AutoPauseEngine {
    enum Action: Equatable {
        case pause
        case resume
    }

    /// How long the stage must hold before music pauses.
    static let engageDelay: TimeInterval = 2
    /// How long the stage must be clear before music resumes —
    /// deliberately longer than the engage delay.
    static let restoreDelay: TimeInterval = 5

    private(set) var engaged = false
    private var stageSince: Date?
    private var clearSince: Date?

    mutating func update(stageActive: Bool, now: Date) -> Action? {
        if stageActive {
            clearSince = nil
            if engaged { return nil }
            if stageSince == nil { stageSince = now }
            if let since = stageSince, now.timeIntervalSince(since) >= Self.engageDelay {
                engaged = true
                stageSince = nil
                return .pause
            }
            return nil
        }

        stageSince = nil
        guard engaged else { return nil }
        if clearSince == nil { clearSince = now }
        if let since = clearSince, now.timeIntervalSince(since) >= Self.restoreDelay {
            engaged = false
            clearSince = nil
            return .resume
        }
        return nil
    }

    mutating func reset() {
        engaged = false
        stageSince = nil
        clearSince = nil
    }
}
