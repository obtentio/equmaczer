// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// A3 channels: resolution is identity-based and remembered — the
/// user's assignment beats the built-in table, the built-in table
/// holds only unambiguous apps, and the active pick honours the pin
/// before priority.
final class ChannelResolverTests: XCTestCase {
    func testBuiltInAssignmentsResolve() {
        XCTAssertEqual(ChannelResolver.channel(forBundleID: "com.spotify.client", userAssignments: [:]), .music)
        XCTAssertEqual(ChannelResolver.channel(forBundleID: "us.zoom.xos", userAssignments: [:]), .calls)
        XCTAssertEqual(ChannelResolver.channel(forBundleID: "org.videolan.vlc", userAssignments: [:]), .film)
        XCTAssertNil(ChannelResolver.channel(forBundleID: "com.example.unknown", userAssignments: [:]))
    }

    func testUserAssignmentBeatsBuiltIn() {
        // Spotify filed under Film by the user stays Film.
        let user: [String: AudioChannel] = ["com.spotify.client": .film]
        XCTAssertEqual(ChannelResolver.channel(forBundleID: "com.spotify.client", userAssignments: user), .film)
    }

    func testBuiltInTableHasNoBrowserAndNoLauncher() {
        // The classification REA's two canonical traps, pinned: a
        // browser is every class at once, and a launcher is not the
        // game. Neither may ever be classified by the table.
        let banned = [
            "com.google.Chrome",
            "com.apple.Safari",
            "org.mozilla.firefox",
            "com.brave.Browser",
            "com.valvesoftware.steam",
            "com.epicgames.launcher",
        ]
        for bundleID in banned {
            XCTAssertNil(
                ChannelResolver.builtInAssignments[bundleID],
                "\(bundleID) must not be in the built-in table"
            )
        }
    }

    func testActivePickHonoursPinThenPriority() {
        XCTAssertEqual(
            ChannelResolver.activeChannel(heard: [.music, .film], pinned: .games),
            .games, "The pin wins even when the pinned channel is not heard"
        )
        XCTAssertEqual(
            ChannelResolver.activeChannel(heard: [.music, .calls, .film], pinned: nil),
            .calls, "Calls outrank everything heard"
        )
        XCTAssertEqual(
            ChannelResolver.activeChannel(heard: [.music, .film], pinned: nil),
            .film, "Film outranks Music"
        )
        XCTAssertNil(ChannelResolver.activeChannel(heard: [], pinned: nil))
    }
}

final class ChannelStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.channels.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRoundTrip() {
        let store = ChannelStore(defaults: defaults)
        XCTAssertEqual(store.load(), ChannelState())

        var state = ChannelState()
        state.assignments["com.example.game"] = .games
        state.treatments[.calls] = "Spoken Word"
        state.pinned = .film
        store.save(state)

        let loaded = store.load()
        XCTAssertEqual(loaded, state)
        XCTAssertEqual(loaded.treatmentName(for: .calls), "Spoken Word")
        XCTAssertEqual(loaded.treatmentName(for: .music), "Flat", "Unset treatments read as Flat")
    }

    func testDialogueSetRoundTrips() {
        let store = ChannelStore(defaults: defaults)
        var state = ChannelState()
        state.dialogue = [.film, .calls]
        store.save(state)
        XCTAssertEqual(store.load().dialogue, [.film, .calls])
    }
}

/// A4 dialogue mode: the clarity set's shape, its eligibility rule,
/// and its composition after the treatment's bands.
final class DialogueClarityTests: XCTestCase {
    func testClarityBandShape() {
        let bands = DialogueClarity.bands
        XCTAssertEqual(bands.count, 3)
        XCTAssertEqual(bands[0].filterType, .lowShelf)
        XCTAssertEqual(bands[0].frequency, 200)
        XCTAssertEqual(bands[0].gain, -2, accuracy: 0.001)
        XCTAssertEqual(bands[1].filterType, .parametric)
        XCTAssertEqual(bands[1].frequency, 2800)
        XCTAssertEqual(bands[1].gain, 3.5, accuracy: 0.001)
        XCTAssertEqual(bands[2].filterType, .highShelf)
        XCTAssertEqual(bands[2].frequency, 9000)
        XCTAssertEqual(bands[2].gain, 1.5, accuracy: 0.001)
        for band in bands {
            XCTAssertLessThanOrEqual(abs(band.gain), 6, "Clarity stays modest — never a loudness button")
            XCTAssertFalse(band.bypass)
        }
    }

    func testDialogueEligibility() {
        XCTAssertTrue(AudioChannel.film.supportsDialogue)
        XCTAssertTrue(AudioChannel.calls.supportsDialogue)
        XCTAssertFalse(AudioChannel.music.supportsDialogue)
        XCTAssertFalse(AudioChannel.games.supportsDialogue)
    }

    func testCompositionAppendsClarityAfterTreatment() {
        let treatment = [
            EQBandConfiguration(frequency: 1000, q: 1, gain: 1, filterType: .parametric, bypass: false)
        ]
        let off = DialogueClarity.composedBands(treatmentBands: treatment, dialogueEnabled: false)
        XCTAssertEqual(off.count, 1)

        let on = DialogueClarity.composedBands(treatmentBands: treatment, dialogueEnabled: true)
        XCTAssertEqual(on.count, 1 + DialogueClarity.bands.count)
        XCTAssertEqual(on[0].frequency, 1000, "Treatment bands stay first")
        XCTAssertEqual(on[1].frequency, 200, "Clarity is appended, not interleaved")
    }
}
