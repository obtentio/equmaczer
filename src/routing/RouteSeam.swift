// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// The routing seam: a pure value type owning the generation counter,
/// the quiescence window that coalesces device events, the read-back
/// tuple a route must match before commit, and the liveness verdict
/// scoped to a generation. All computation is pure and testable; the
/// coordinator delegates decisions here rather than embedding the
/// logic inline.
///
/// Mirrors audit/SEAM-EPOCH-DESIGN.md sections 1–4. Every route
/// generation bump invalidates in-flight async work (liveness proofs,
/// restages). The quiescence window ensures a storm of device
/// notifications becomes a single commit against the settled state. The
/// read-back tuple guards against silent wrong-rate routes. The liveness
/// verdict scopes the frame-counter proof to the generation it ran under.
struct RouteSeam: Equatable {

    // MARK: - Generation (S1)

    /// Monotonically increasing generation counter. Bumped by every
    /// event that changes what "the current route" means — output
    /// device change, nominal sample-rate change, capture-mode change,
    /// wake, or watchdog retry.
    private(set) var generation: UInt64 = 0

    /// Advances the generation and returns the new value. Unsigned
    /// wrapping add: safe in practice (a UInt64 at 1 kHz takes ~580
    /// million years to wrap) and cannot trap.
    @discardableResult
    mutating func advanceGeneration() -> UInt64 {
        generation &+= 1
        return generation
    }

    /// Whether a stamp taken under an earlier generation is still
    /// current. A proof that completes under an older generation is
    /// discarded — the mid-proof storm case this is built for.
    func isCurrent(_ stamp: UInt64) -> Bool {
        generation == stamp
    }

    /// The liveness watchdog's verdict for one completed proof, scoped
    /// to the generation under which it ran. A stale generation or a
    /// superseded pipeline is discarded before any frame-counter
    /// judgment.
    enum LivenessVerdict: Equatable {
        /// Generation/stamp no longer matches (or routing is no longer
        /// active): discard the proof, start no retry.
        case superseded
        /// Current route, no frames and no process producing output: keep waiting.
        case idle
        /// Current route, frames stalled while a process produces output: dead.
        case dead
        /// Current route, frames advancing: the route is alive.
        case alive
    }

    func livenessVerdict(
        stamp: UInt64,
        pipelineStillCurrent: Bool,
        statusActive: Bool,
        framesAdvanced: Bool,
        processProducingOutput: Bool
    ) -> LivenessVerdict {
        guard isCurrent(stamp), pipelineStillCurrent, statusActive else {
            return .superseded
        }
        if framesAdvanced { return .alive }
        return processProducingOutput ? .dead : .idle
    }

    // MARK: - Quiescence (S2)

    /// The coalescing window that collects device events before one
    /// restart. 150 ms ordinarily, 250 ms after a wake event, so a storm
    /// of five notifications becomes one restart against the final state.
    enum Window: Equatable {
        case normal
        case wake

        var duration: TimeInterval {
            switch self {
            case .normal: return 0.150
            case .wake: return 0.250
            }
        }
    }

    private(set) var pendingWindow: Window?
    private(set) var deadline: TimeInterval?

    /// When the open window started. The deadline is anchored here, so
    /// a storm cannot slide the commit out of reach: the window closes
    /// one window length after the first event whatever arrives after.
    /// (A sliding window would let continuous churn starve the commit
    /// indefinitely — the opposite of the design's bounded coalescing.)
    private(set) var windowOpenedAt: TimeInterval?

    /// Opens (or extends) a coalescing window at `now`. Returns true:
    /// the caller should (re)schedule a commit attempt at `deadline`.
    /// A wake window outranks a normal one and lengthens the interval
    /// measured from the window's open; it never shortens the deadline
    /// already set.
    @discardableResult
    mutating func noteEvent(at now: TimeInterval, window: Window) -> Bool {
        guard pendingWindow != nil, let opened = windowOpenedAt else {
            // First event in this window: it opens here and sets the anchor.
            windowOpenedAt = now
            pendingWindow = window
            deadline = now + window.duration
            return true
        }
        if window == .wake {
            pendingWindow = .wake
        }
        if let pending = pendingWindow {
            deadline = max(deadline ?? 0, opened + pending.duration)
        }
        return true
    }

    /// Whether the window has elapsed at `now` and a commit is due.
    func isCommitDue(at now: TimeInterval) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }

    /// Closes the window and returns the window type that committed, or
    /// `nil` when nothing is pending — the stale-timer guard: a timer
    /// that fires twice (or after a wake extended the window) commits once.
    ///
    /// A commit is itself a route change: it advances the generation so
    /// every proof and restage started inside the window is invalidated
    /// by the commit, together. One window, one commit, one generation.
    mutating func closeWindow(at now: TimeInterval) -> Window? {
        guard isCommitDue(at: now) else { return nil }
        let window = pendingWindow
        pendingWindow = nil
        deadline = nil
        windowOpenedAt = nil
        advanceGeneration()
        return window
    }

    /// Cancels any pending window so a coalesced restart cannot fire
    /// after teardown (`stopRouting`).
    mutating func cancelWindow() {
        pendingWindow = nil
        deadline = nil
        windowOpenedAt = nil
    }

    /// The quiescent commit's decision: restart only when the settled
    /// route differs from the running one, or nothing is running. A wake
    /// or a storm that settles back onto the live route restarts
    /// nothing (design S2: wake with a stable route, zero restarts).
    /// An unreadable settled tuple (`nil`) restarts — the reconfigure
    /// will produce an honest status.
    static func commitNeedsRestart(settled: RouteTuple?, running: RouteTuple?, statusActive: Bool) -> Bool {
        guard statusActive, let settled, let running else { return true }
        return !matches(intent: settled, readBack: running)
    }

    // MARK: - Read-back (S3)

    /// The committed route's identity: what must be read back and
    /// verified before status becomes `.active`.
    struct RouteTuple: Equatable {
        var outputUID: String
        var sampleRate: Double
        var captureMode: CaptureMode
    }

    /// Whether the read-back state matches the intended tuple. A
    /// mismatch is not an error — it is a new event (advance generation,
    /// recoalesce). A nil read-back (rate/HAL unavailable) defaults to
    /// match: absence of a reading is not evidence of a wrong route, and
    /// failing on it would change the happy path on machines where the
    /// API returns nil.
    static func matches(intent: RouteTuple, readBack: RouteTuple?) -> Bool {
        guard let readBack else { return true }
        return intent.outputUID == readBack.outputUID
            && abs(intent.sampleRate - readBack.sampleRate) < 1
            && intent.captureMode == readBack.captureMode
    }
}
