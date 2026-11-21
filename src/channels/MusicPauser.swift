// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import AppKit
import Foundation
import os.log

/// Pauses and resumes the scriptable music apps (A8), the
/// transferable half of Background Music's auto-pause mechanism.
///
/// Discipline: an app is only ever spoken to when it is already
/// running (an AppleScript `tell` would launch it), its own
/// reported player state decides whether it gets paused, and every
/// decision is taken on that state — never assumed.
enum MusicPauser {
    struct Target: Equatable {
        let bundleID: String
        let appName: String
    }

    /// The music apps with verifiable AppleScript player control.
    /// (TIDAL and Deezer are classified as Music by the channel
    /// table, but their scripting support isn't verifiable, so they
    /// are never auto-paused — the pane says which apps are.)
    static let targets: [Target] = [
        Target(bundleID: "com.spotify.client", appName: "Spotify"),
        Target(bundleID: "com.apple.Music", appName: "Music"),
    ]

    private static let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "MusicPauser")

    static func isRunning(_ target: Target) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).isEmpty
    }

    /// The app's own report of its player state ("playing",
    /// "paused", "stopped"), or nil when it can't be asked.
    static func playerState(_ target: Target) -> String? {
        run("tell application \"\(target.appName)\" to get player state as string")
    }

    static func pause(_ target: Target) {
        _ = run("tell application \"\(target.appName)\" to pause")
    }

    static func play(_ target: Target) {
        _ = run("tell application \"\(target.appName)\" to play")
    }

    private static func run(_ source: String) -> String? {
        var errorInfo: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            logger.error("AppleScript failed: \(String(describing: errorInfo), privacy: .public)")
            return nil
        }
        return result?.stringValue
    }
}
