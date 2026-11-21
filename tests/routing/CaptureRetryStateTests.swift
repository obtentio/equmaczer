// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

final class CaptureRetryStateTests: XCTestCase {
    func testFirstDeadTapRetriesWithoutNoticeOrFailedMode() {
        var state = CaptureRetryState()
        XCTAssertEqual(dead(.processTap, state: &state), .processTap)
        XCTAssertNil(state.notice)
        XCTAssertTrue(state.failedCaptureModes.isEmpty)
    }

    func testSecondDeadTapFallsBackWithNotice() {
        for shared in [false, true] {
            var state = CaptureRetryState()
            XCTAssertEqual(dead(.processTap, state: &state, shared: shared), .processTap)
            let next: CaptureMode = shared ? .sharedMemory : .halInput
            XCTAssertEqual(dead(.processTap, state: &state, shared: shared), next)
            XCTAssertEqual(state.failedCaptureModes, [.processTap])
            XCTAssertEqual(state.notice, "Process Tap heard no audio — if music was playing, check the audio-capture permission (System Settings → Privacy & Security → Screen & System Audio Recording). Switched to \(next.displayName).")
        }
    }

    func testFreshSessionResetsTapRetryAndFailures() {
        var state = CaptureRetryState()
        _ = dead(.processTap, state: &state)
        _ = dead(.processTap, state: &state)
        XCTAssertNotNil(state.notice)
        // The fresh, non-retry reconfigure replaces the session state.
        state = CaptureRetryState()
        XCTAssertEqual(dead(.processTap, state: &state), .processTap)
        XCTAssertNil(state.notice)
        XCTAssertTrue(state.failedCaptureModes.isEmpty)
        XCTAssertEqual(dead(.processTap, state: &state), .sharedMemory)
    }

    func testDeadRoutesExhaustAfterOneTapRebuild() {
        var state = CaptureRetryState()
        XCTAssertEqual(dead(.processTap, state: &state), .processTap)
        XCTAssertEqual(dead(.processTap, state: &state), .sharedMemory)
        XCTAssertEqual(dead(.sharedMemory, state: &state), .halInput)
        XCTAssertNil(dead(.halInput, state: &state))
        XCTAssertEqual(state.failedCaptureModes, Set(CaptureMode.allCases))
        XCTAssertEqual(state.notice, "No capture route produced audio — routing stopped.")
        XCTAssertNil(dead(.processTap, state: &state))
    }

    func testOtherModesFallBackImmediately() {
        var state = CaptureRetryState()
        XCTAssertEqual(state.handleDeadRoute(
            .sharedMemory, preference: .sharedMemory,
            isManualMode: false, supportsSharedMemory: true
        ), .halInput)
        XCTAssertEqual(state.failedCaptureModes, [.sharedMemory])
        XCTAssertEqual(state.notice, "Shared Memory produced no audio — switched to HAL Input.")

        state = CaptureRetryState()
        XCTAssertNil(state.handleDeadRoute(
            .halInput, preference: .processTap,
            isManualMode: true, supportsSharedMemory: true
        ))
        XCTAssertEqual(state.failedCaptureModes, [.halInput])
        XCTAssertEqual(state.notice, "No capture route produced audio — routing stopped.")
    }

    private func dead(
        _ mode: CaptureMode, state: inout CaptureRetryState, shared: Bool = true
    ) -> CaptureMode? {
        state.handleDeadRoute(
            mode, preference: .processTap,
            isManualMode: false, supportsSharedMemory: shared
        )
    }
}
