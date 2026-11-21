// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Combine
import Foundation
import os.log

/// One thing that really happened, with the moment it happened.
struct ActivityEvent: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case route, scene, channel, preset, driver
    }

    var id = UUID()
    let date: Date
    let kind: Kind
    let text: String
}

/// Anything that can be told an event happened. Callers depend on
/// this, not on the journal.
@MainActor
protocol ActivityRecording: AnyObject {
    func record(_ kind: ActivityEvent.Kind, _ text: String)
}

/// The real, bounded, persisted event journal (Settings › Driver ›
/// Activity). Rows are written only by the code path where the event
/// happens — never backfilled or invented. Main-actor only: the audio
/// thread never records. Newest first; the oldest is dropped at
/// capacity.
@MainActor
final class ActivityJournal: ObservableObject, ActivityRecording {
    static let defaultCapacity = 200

    @Published private(set) var events: [ActivityEvent]

    let capacity: Int
    private let defaults: UserDefaults
    private let key = "equaliser.activity.v1"
    private let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "ActivityJournal")

    init(defaults: UserDefaults = .standard, capacity: Int = ActivityJournal.defaultCapacity) {
        self.defaults = defaults
        self.capacity = max(1, capacity)
        var loaded: [ActivityEvent] = []
        if let data = defaults.data(forKey: key) {
            do {
                loaded = try JSONDecoder().decode([ActivityEvent].self, from: data)
            } catch {
                logger.error("Failed to decode activity journal: \(error.localizedDescription)")
            }
        }
        events = Array(loaded.prefix(max(1, capacity)))
    }

    func record(_ kind: ActivityEvent.Kind, _ text: String) {
        record(kind, text, at: Date())
    }

    func record(_ kind: ActivityEvent.Kind, _ text: String, at date: Date) {
        events.insert(ActivityEvent(date: date, kind: kind, text: text), at: 0)
        if events.count > capacity { events.removeLast(events.count - capacity) }
        persist()
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(events), forKey: key)
        } catch {
            logger.error("Failed to encode activity journal: \(error.localizedDescription)")
        }
    }
}
