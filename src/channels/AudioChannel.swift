// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// A channel (A3): a named group of apps sharing one treatment —
/// Sonar's model of a few named targets instead of a per-app matrix.
/// Channels are assigned by bundle identity, never inferred from
/// audio content (the context-classification REA: declared/identity
/// signals beat inference everywhere they ship).
enum AudioChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case music
    case calls
    case film
    case games

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .music: return "Music"
        case .calls: return "Calls"
        case .film: return "Film"
        case .games: return "Games"
        }
    }

    /// Which channel wins when several are heard at once: the
    /// interactive before the passive, a call before everything.
    /// Lower wins.
    var priority: Int {
        switch self {
        case .calls: return 0
        case .games: return 1
        case .film: return 2
        case .music: return 3
        }
    }

    /// Whether Dialogue mode (A4) may apply to this channel. Film
    /// and Calls carry speech the listener is trying to follow;
    /// on Music the same curve degenerates into a loudness button,
    /// and Games carry their own dialogue mixes — the sweep's named
    /// failure mode, closed here in the model rather than merely
    /// hidden in the layout.
    var supportsDialogue: Bool {
        switch self {
        case .film, .calls: return true
        case .music, .games: return false
        }
    }
}

/// Pure channel resolution, kept separate from the controller so it
/// is tested directly: assignment lookup and the active pick.
enum ChannelResolver {
    /// Built-in assignments for apps whose identity is unambiguous.
    /// Two deliberate absences, both canonical classification traps:
    /// **no browser** (a browser is every class at once, tab by tab)
    /// and **no game launcher** (the launcher is not the game).
    /// Everything not listed here is ask-once: it is remembered the
    /// first time the user assigns it in the Channels panel.
    static let builtInAssignments: [String: AudioChannel] = [
        // Music
        "com.apple.Music": .music,
        "com.spotify.client": .music,
        "com.tidal.desktop": .music,
        "com.deezer.Deezer": .music,
        // Calls
        "com.apple.FaceTime": .calls,
        "us.zoom.xos": .calls,
        "com.microsoft.teams2": .calls,
        "com.hnc.Discord": .calls,
        "com.skype.skype": .calls,
        // Film
        "com.apple.TV": .film,
        "com.apple.QuickTimePlayerX": .film,
        "org.videolan.vlc": .film,
        "com.colliderli.iina": .film,
    ]

    /// The channel for one app: the user's remembered assignment
    /// wins over the built-in table; unassigned and unknown is nil.
    static func channel(forBundleID bundleID: String, userAssignments: [String: AudioChannel]) -> AudioChannel? {
        userAssignments[bundleID] ?? builtInAssignments[bundleID]
    }

    /// The channel whose treatment applies: the user's pin if one is
    /// set, else the highest-priority channel currently heard, else
    /// nil (nothing heard — the caller keeps the current treatment).
    static func activeChannel(heard: Set<AudioChannel>, pinned: AudioChannel?) -> AudioChannel? {
        if let pinned { return pinned }
        return heard.min(by: { $0.priority < $1.priority })
    }
}
