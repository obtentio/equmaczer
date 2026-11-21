// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Combine
import Foundation
import os.log

/// Accumulates the week's estimated dose (A6) and publishes the
/// last 7 days for the Hearing pane. Samples the level provider
/// every 2 seconds; gaps longer than 10 s (sleep, restarts) are
/// never credited — unmeasured time is not exposure evidence.
@MainActor
final class DoseController: ObservableObject {
    struct DayDose: Identifiable {
        let dayKey: String
        let label: String
        let fraction: Double
        var id: String { dayKey }
    }

    /// The last 7 days, oldest first, today last.
    @Published private(set) var week: [DayDose] = []

    /// The week's total as a percentage of the reference budget.
    @Published private(set) var weeklyPercent: Double = 0

    /// Supplies the current output level: RMS in dBFS and the
    /// device volume in dB. Nil when nothing is playing. Wired by
    /// `EqumaczerStore` (the A1 provider pattern).
    var levelProvider: (() -> (rmsDB: Double, volumeDB: Double)?)?

    private let store: DoseStore
    private var buckets: [String: Double]
    private var sampleTask: Task<Void, Never>?
    private var lastSampleAt: Date?
    private let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "DoseController")

    init(store: DoseStore = DoseStore()) {
        self.store = store
        self.buckets = store.load()
    }

    func start() {
        refreshWeek()
        sampleTask?.cancel()
        sampleTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stop() {
        sampleTask?.cancel()
        sampleTask = nil
    }

    private func sample() {
        let now = Date()
        defer { lastSampleAt = now }
        guard let last = lastSampleAt,
              let level = levelProvider?()
        else { return }
        let elapsed = now.timeIntervalSince(last)
        guard elapsed > 0, elapsed < 10 else { return }

        let levelDBA = DoseMath.estimatedLevelDBA(outputRmsDBFS: level.rmsDB, volumeDB: level.volumeDB)
        let increment = DoseMath.doseFraction(levelDBA: levelDBA, durationSeconds: elapsed)
        guard increment > 0 else { return }

        let key = DoseStore.dayKey(for: now)
        buckets[key, default: 0] += increment
        store.save(buckets, now: now)
        refreshWeek()
    }

    private func refreshWeek() {
        let calendar = Calendar.current
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "EEEEE"
        var days: [DayDose] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let key = DoseStore.dayKey(for: date)
            days.append(DayDose(
                dayKey: key,
                label: labelFormatter.string(from: date),
                fraction: buckets[key] ?? 0
            ))
        }
        week = days
        weeklyPercent = days.reduce(0) { $0 + $1.fraction } * 100
    }
}
