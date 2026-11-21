// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation
import os.log

/// Daily dose buckets (A6): date key (yyyy-MM-dd) → fraction of the
/// weekly reference budget spent that day. JSON in UserDefaults,
/// the family pattern; buckets older than 14 days are pruned on
/// save — the view shows 7, and a fortnight of history is plenty
/// for an estimate.
final class DoseStore {
    private let defaults: UserDefaults
    private let key = "equaliser.dose.v1"
    private let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "DoseStore")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    func load() -> [String: Double] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        do {
            return try JSONDecoder().decode([String: Double].self, from: data)
        } catch {
            logger.error("Failed to decode dose buckets: \(error.localizedDescription)")
            return [:]
        }
    }

    func save(_ buckets: [String: Double], now: Date = Date()) {
        let cutoff = Self.dayKey(for: Calendar.current.date(byAdding: .day, value: -13, to: now) ?? now)
        let pruned = buckets.filter { $0.key >= cutoff }
        do {
            let data = try JSONEncoder().encode(pruned)
            defaults.set(data, forKey: key)
        } catch {
            logger.error("Failed to encode dose buckets: \(error.localizedDescription)")
        }
    }
}
