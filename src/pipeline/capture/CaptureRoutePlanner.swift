// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// Ordered capture-route candidates and retry selection.
///
/// `CaptureModePolicy` answers the first-choice question; this planner
/// owns the sequence when a chosen route starts but produces no audio
/// (the liveness watchdog's territory). The two must agree on the
/// first candidate — a test pins that equivalence across the whole
/// input grid so they cannot drift apart.
///
/// Fallback order after the preference: shared memory (when the
/// driver supports it), then HAL input. The process tap only ever
/// runs as the explicit preference, never as an automatic fallback:
/// it replaces the output path with an aggregate device, which is a
/// bigger change than a capture retry should make unasked.
enum CaptureRoutePlanner {

    /// All routes worth attempting for these conditions, best first.
    static func orderedCandidates(
        preference: CaptureMode,
        isManualMode: Bool,
        supportsSharedMemory: Bool
    ) -> [CaptureMode] {
        if isManualMode {
            return [.halInput]
        }

        var order: [CaptureMode] = []
        func add(_ mode: CaptureMode) {
            if !order.contains(mode) { order.append(mode) }
        }

        // The preference leads, except an incapable shared-memory
        // preference, which the policy resolves straight to HAL input.
        if preference != .sharedMemory || supportsSharedMemory {
            add(preference)
        }
        if supportsSharedMemory {
            add(.sharedMemory)
        }
        add(.halInput)
        return order
    }

    /// The next route to try after `failed` routes produced no audio,
    /// or nil when every candidate has failed (give up honestly
    /// rather than loop or sit silent).
    static func nextCandidate(
        after failed: Set<CaptureMode>,
        preference: CaptureMode,
        isManualMode: Bool,
        supportsSharedMemory: Bool
    ) -> CaptureMode? {
        orderedCandidates(
            preference: preference,
            isManualMode: isManualMode,
            supportsSharedMemory: supportsSharedMemory
        ).first { !failed.contains($0) }
    }
}
