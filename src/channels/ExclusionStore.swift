// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation
import OSLog

/// D2: the never-process list. Apps on it are excluded from the
/// process tap by bundle ID, so their sound reaches the output
/// untouched — the Game Mode / DAW answer: an excluded app never
/// waits on this app's processing at all. Persisted like the
/// channel state (JSON in UserDefaults).
struct ExclusionState: Codable {
    var bundleIDs: [String] = []
    /// Display names captured when the app was added, so the
    /// list still reads well when the app is not installed or
    /// not running.
    var names: [String: String] = [:]
}

final class ExclusionStore: ObservableObject {
    @Published private(set) var state: ExclusionState

    private let defaults: UserDefaults
    private let key = "equaliser.exclusions.v1"
    private let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "ExclusionStore")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ExclusionState.self, from: data) {
            state = decoded
        } else {
            state = ExclusionState()
        }
    }

    var bundleIDs: [String] { state.bundleIDs }

    func contains(_ bundleID: String) -> Bool {
        state.bundleIDs.contains(bundleID)
    }

    func exclude(bundleID: String, name: String) {
        guard !state.bundleIDs.contains(bundleID) else { return }
        state.bundleIDs.append(bundleID)
        state.bundleIDs.sort()
        state.names[bundleID] = name
        save()
    }

    func include(bundleID: String) {
        state.bundleIDs.removeAll { $0 == bundleID }
        state.names.removeValue(forKey: bundleID)
        save()
    }

    func name(for bundleID: String) -> String {
        state.names[bundleID] ?? bundleID
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(state), forKey: key)
        } catch {
            logger.error("Failed to save exclusions: \(error.localizedDescription)")
        }
    }
}
