import XCTest
@testable import equmaczer

@MainActor
final class ActivityJournalTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "equmaczer.activity-tests.\(UUID())")!
    }

    func testRecordsNewestFirstWithTimestampAndKind() {
        let journal = ActivityJournal(defaults: defaults())
        XCTAssertTrue(journal.events.isEmpty, "A fresh journal has no backfilled rows")
        let t1 = Date(timeIntervalSince1970: 1_000)
        let t2 = Date(timeIntervalSince1970: 2_000)
        journal.record(.preset, "Loaded preset Warm", at: t1)
        journal.record(.route, "Output set to Desk", at: t2)
        XCTAssertEqual(journal.events.map(\.text), ["Output set to Desk", "Loaded preset Warm"])
        XCTAssertEqual(journal.events.map(\.date), [t2, t1])
        XCTAssertEqual(journal.events.map(\.kind), [.route, .preset])
    }

    func testBoundedDropsOldest() {
        let journal = ActivityJournal(defaults: defaults(), capacity: 3)
        for i in 1...5 { journal.record(.scene, "event \(i)") }
        XCTAssertEqual(journal.events.map(\.text), ["event 5", "event 4", "event 3"])
    }

    func testPersistsAcrossInstancesAndRespectsCapacityOnLoad() {
        let storage = defaults()
        let first = ActivityJournal(defaults: storage, capacity: 10)
        for i in 1...4 { first.record(.driver, "event \(i)") }
        let second = ActivityJournal(defaults: storage, capacity: 10)
        XCTAssertEqual(second.events.map(\.text), ["event 4", "event 3", "event 2", "event 1"])
        let smaller = ActivityJournal(defaults: storage, capacity: 2)
        XCTAssertEqual(smaller.events.map(\.text), ["event 4", "event 3"])
    }

    func testStoreRecordsPresetLoadAndChannelSwitchOnlyWhenTheyHappen() {
        let storage = defaults()
        let journal = ActivityJournal(defaults: storage)
        let store = EqumaczerStore(persistence: AppStatePersistence(storage: storage),
            channelStore: ChannelStore(defaults: storage), activityJournal: journal, startAutomation: false)
        XCTAssertFalse(journal.events.contains { $0.kind == .preset })
        let name = store.presetManager.presets.first?.metadata.name
        guard let name else { return XCTFail("No preset to load") }
        store.loadPreset(named: name)
        XCTAssertEqual(journal.events.first?.kind, .preset)
        XCTAssertEqual(journal.events.first?.text, "Loaded preset \(name)")
        store.loadPreset(named: "No such preset")
        XCTAssertEqual(journal.events.filter { $0.kind == .preset }.count, 1, "A failed load is not an event")
    }
}
