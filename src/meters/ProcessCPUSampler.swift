// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// This process's CPU use, as a percentage of one core, from
/// getrusage deltas (B3). Deliberately ours only: the audio
/// server's load is not readable by an unprivileged app, and the
/// health panel shows the mismatch that causes it instead of
/// inventing a figure. First sample is nil (no delta yet).
final class ProcessCPUSampler {
    private var lastCPUSeconds: Double?
    private var lastWallSeconds: Double?

    func sample() -> Double? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        let cpu = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        let wall = ProcessInfo.processInfo.systemUptime
        defer {
            lastCPUSeconds = cpu
            lastWallSeconds = wall
        }
        guard let lastCPUSeconds, let lastWallSeconds, wall > lastWallSeconds else {
            return nil
        }
        return (cpu - lastCPUSeconds) / (wall - lastWallSeconds) * 100
    }
}
