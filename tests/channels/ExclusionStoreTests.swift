// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// D2: the never-process list persists, deduplicates, keeps
/// its names, and forgets cleanly.
final class ExclusionStoreTests: XCTestCase {
    private func makeStore() -> (ExclusionStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "ExclusionStoreTests-\(UUID().uuidString)")!
        return (ExclusionStore(defaults: defaults), defaults)
    }

    func testExcludeIncludeRoundTrip() {
        let (store, defaults) = makeStore()
        store.exclude(bundleID: "com.game.studio", name: "Game")
        store.exclude(bundleID: "com.daw.maker", name: "DAW")
        XCTAssertEqual(store.bundleIDs, ["com.daw.maker", "com.game.studio"], "kept sorted")
        XCTAssertTrue(store.contains("com.game.studio"))
        XCTAssertEqual(store.name(for: "com.daw.maker"), "DAW")

        let reloaded = ExclusionStore(defaults: defaults)
        XCTAssertEqual(reloaded.bundleIDs, store.bundleIDs)
        XCTAssertEqual(reloaded.name(for: "com.game.studio"), "Game")

        store.include(bundleID: "com.game.studio")
        XCTAssertFalse(store.contains("com.game.studio"))
        XCTAssertEqual(store.name(for: "com.game.studio"), "com.game.studio", "name forgotten with the entry")
    }

    func testExcludeIsIdempotent() {
        let (store, _) = makeStore()
        store.exclude(bundleID: "com.game.studio", name: "Game")
        store.exclude(bundleID: "com.game.studio", name: "Game Again")
        XCTAssertEqual(store.bundleIDs.count, 1)
        XCTAssertEqual(store.name(for: "com.game.studio"), "Game", "the first name stands")
    }
}
