// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).

/// How a call is handled once the stage holds.
enum CallDuckAction: Equatable {
    case duck
    case pause
}

/// Pure choice of method for the "During calls" setting. The sound driver
/// carries one mixed stream and cannot lower only some apps, so Lower falls
/// back to Pause there. It never switches the route.
enum CallDuckPolicy {
    static func action(mode: DuringCallsMode, canDuck: Bool) -> CallDuckAction? {
        switch mode {
        case .nothing: nil
        case .pause: .pause
        case .lower: canDuck ? .duck : .pause
        }
    }

    static let driverNote = "On the sound driver, music pauses instead. Process Tap can lower it."

    static func caption(for mode: DuringCallsMode) -> String {
        mode == .pause
            ? "Pause Spotify and Apple Music while a call or video plays; resume after. Your own play press always wins."
            : "Lower music and other sound while a call or video plays. Your call stays at full volume."
    }
}
