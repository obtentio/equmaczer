// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).

/// Session-local liveness recovery: one tap rebuild, then bounded fallback.
struct CaptureRetryState {
    private(set) var failedCaptureModes: Set<CaptureMode> = []
    private(set) var notice: String?
    private var processTapRetried = false

    mutating func handleDeadRoute(
        _ mode: CaptureMode,
        preference: CaptureMode,
        isManualMode: Bool,
        supportsSharedMemory: Bool
    ) -> CaptureMode? {
        if mode == .processTap && !processTapRetried {
            processTapRetried = true
            return .processTap
        }

        failedCaptureModes.insert(mode)
        let next = CaptureRoutePlanner.nextCandidate(
            after: failedCaptureModes,
            preference: preference,
            isManualMode: isManualMode,
            supportsSharedMemory: supportsSharedMemory
        )
        if let next {
            if mode == .processTap {
                notice = "Process Tap heard no audio — if music was playing, check the audio-capture permission (System Settings → Privacy & Security → Screen & System Audio Recording). Switched to \(next.displayName)."
            } else {
                notice = "\(mode.displayName) produced no audio — switched to \(next.displayName)."
            }
        } else {
            notice = "No capture route produced audio — routing stopped."
        }
        return next
    }
}
