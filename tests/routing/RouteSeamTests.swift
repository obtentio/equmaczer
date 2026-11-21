// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// RouteSeam tests: S4 validation of generation counting, quiescence window,
/// read-back verification, and liveness verdict correctness.
final class RouteSeamTests: XCTestCase {
    
    var seam: RouteSeam!
    
    override func setUp() {
        super.setUp()
        seam = RouteSeam()
    }
    
    func test_initial_generation_zero() {
        XCTAssertEqual(seam.generation, 0)
    }
    
    func test_generation_advances_monotonically() {
        let initial = seam.generation
        _ = seam.advanceGeneration()
        XCTAssertGreaterThan(seam.generation, initial)
        // Check that generation is monotonic by advancing multiple times
        for _ in 0..<10 {
            _ = seam.advanceGeneration()
        }
        // Should not wrap around to zero in practical test (UInt64)
        XCTAssertNotEqual(seam.generation, 0)
    }
    
    func test_isCurrent_true_after_advance() {
        // A stamp taken at the current generation is current — that is
        // exactly what lets a proof running under it proceed.
        XCTAssertTrue(seam.isCurrent(seam.generation))
        let stamp = seam.advanceGeneration()
        XCTAssertTrue(seam.isCurrent(stamp))
        // An old stamp is never current again: a proof completed under
        // an earlier generation must be discarded (never acted on).
        XCTAssertFalse(seam.isCurrent(stamp - 1))
        seam.advanceGeneration()
        seam.advanceGeneration()
        XCTAssertFalse(seam.isCurrent(stamp))
    }
    
    func test_liveness_verdict_superseded() {
        // Stamp older than current generation
        seam.advanceGeneration()
        let stamp = seam.generation - 1
        let verdict = seam.livenessVerdict(
            stamp: stamp,
            pipelineStillCurrent: true,
            statusActive: true,
            framesAdvanced: false, processProducingOutput: true
        )
        XCTAssertEqual(verdict, .superseded)
    }
    
    func test_liveness_verdict_dead() {
        // Current generation with no frame advancement
        let verdict = seam.livenessVerdict(
            stamp: seam.generation,
            pipelineStillCurrent: true,
            statusActive: true,
            framesAdvanced: false, processProducingOutput: true
        )
        XCTAssertEqual(verdict, .dead)
    }
    
    func test_liveness_verdict_alive() {
        // Current generation with frame advancement
        seam.advanceGeneration()
        let verdict = seam.livenessVerdict(
            stamp: seam.generation,
            pipelineStillCurrent: true,
            statusActive: true,
            framesAdvanced: true, processProducingOutput: true
        )
        XCTAssertEqual(verdict, .alive)
    }
    
    func test_quiet_route_stays_idle_without_retry_or_fallback_notice() {
        for mode in CaptureMode.allCases {
            var retry = CaptureRetryState()
            var currentMode: CaptureMode? = mode
            for _ in 0..<5 {
                let verdict = seam.livenessVerdict(
                    stamp: seam.generation, pipelineStillCurrent: true, statusActive: true,
                    framesAdvanced: false, processProducingOutput: false
                )
                XCTAssertEqual(verdict, .idle)
                if verdict == .dead {
                    currentMode = retry.handleDeadRoute(mode, preference: mode,
                        isManualMode: false, supportsSharedMemory: true)
                }
                XCTAssertEqual(currentMode, mode)
                XCTAssertTrue(retry.failedCaptureModes.isEmpty)
                XCTAssertNil(retry.notice)
            }
        }
    }

    func test_idle_tap_rearms_then_retries_and_falls_back_when_output_stalls() {
        var retry = CaptureRetryState()
        for playing in [false, false, true, false, true] {
            let verdict = seam.livenessVerdict(
                stamp: seam.generation, pipelineStillCurrent: true, statusActive: true,
                framesAdvanced: false, processProducingOutput: playing
            )
            if !playing {
                XCTAssertEqual(verdict, .idle)
                XCTAssertNil(retry.notice)
                continue
            }
            XCTAssertEqual(verdict, .dead)
            let next = retry.handleDeadRoute(.processTap, preference: .processTap,
                isManualMode: false, supportsSharedMemory: true)
            if retry.failedCaptureModes.isEmpty {
                XCTAssertEqual(next, .processTap)
                XCTAssertNil(retry.notice)
            } else {
                XCTAssertEqual(next, .sharedMemory)
                XCTAssertEqual(retry.failedCaptureModes, [.processTap])
                XCTAssertNotNil(retry.notice)
            }
        }
        XCTAssertEqual(retry.failedCaptureModes, [.processTap])
    }

    func test_frames_prove_alive_regardless_of_output_activity() {
        for playing in [false, true] {
            XCTAssertEqual(seam.livenessVerdict(
                stamp: seam.generation, pipelineStillCurrent: true, statusActive: true,
                framesAdvanced: true, processProducingOutput: playing
            ), .alive)
        }
    }

    func test_quiet_stale_proof_is_superseded() {
        let stamp = seam.generation
        seam.advanceGeneration()
        XCTAssertEqual(seam.livenessVerdict(
            stamp: stamp, pipelineStillCurrent: true, statusActive: true,
            framesAdvanced: false, processProducingOutput: false
        ), .superseded)
    }

    func test_read_back_matches_intent() {
        // Simulate route tuple
        let intent = RouteSeam.RouteTuple(
            outputUID: "device-uid-123",
            sampleRate: 44100.0,
            captureMode: .processTap
        )
        
        // Match when readBack is nil (HAL unavailable)
        XCTAssertTrue(RouteSeam.matches(intent: intent, readBack: nil))
        
        // Match when readBack matches
        let readBack = RouteSeam.RouteTuple(
            outputUID: "device-uid-123",
            sampleRate: 44100.0,
            captureMode: .processTap
        )
        XCTAssertTrue(RouteSeam.matches(intent: intent, readBack: readBack))
        
        // Mismatch on sample rate
        let mismatchedReadBack = RouteSeam.RouteTuple(
            outputUID: "device-uid-123",
            sampleRate: 48000.0,
            captureMode: .processTap
        )
        XCTAssertFalse(RouteSeam.matches(intent: intent, readBack: mismatchedReadBack))
    }
    
    func test_quiescence_window_coalesces_events() {
        let now = ProcessInfo.processInfo.systemUptime
        let normalWindow = RouteSeam.Window.normal
        let wakeWindow = RouteSeam.Window.wake
        
        // Note three events within normal window
        seam.noteEvent(at: now, window: .normal)
        seam.noteEvent(at: now + 0.05, window: .normal)
        seam.noteEvent(at: now + 0.1, window: .normal)
        
        // Deadline should be after the last event + window duration
        let expectedDeadline = now + normalWindow.duration
        XCTAssertEqual(seam.deadline, expectedDeadline)
        
        // Now extend to wake window (250ms)
        let extendedDeadline = now + wakeWindow.duration
        seam.noteEvent(at: now + 0.15, window: .wake)
        XCTAssertEqual(seam.deadline, extendedDeadline)
        
        // Close window should return the wake window
        let closed = seam.closeWindow(at: now + 0.3)
        XCTAssertEqual(closed, .wake)
    }
    
    func test_quiescence_window_commits_once() {
        // Create a storm of 5 events within normal window
        let now = ProcessInfo.processInfo.systemUptime
        for _ in 0..<5 {
            seam.noteEvent(at: now, window: .normal)
        }
        
        // Commit should happen once
        let firstCommit = seam.closeWindow(at: now + 0.2)
        XCTAssertEqual(firstCommit, .normal)
        
        // Second close should be nil (stale guard)
        let secondCommit = seam.closeWindow(at: now + 0.3)
        XCTAssertNil(secondCommit)
        
        // Generation should have advanced once
        XCTAssertEqual(seam.generation, 1)
    }
    
    func test_quiescence_window_cancels_pending_commit() {
        // Note event and start commit countdown
        let now = ProcessInfo.processInfo.systemUptime
        seam.noteEvent(at: now, window: .normal)
        // Simulate commit attempt before deadline
        let commitTime = now + 0.1
        let committed = seam.closeWindow(at: commitTime)
        XCTAssertNil(committed)
        
        // Cancel should reset state
        seam.cancelWindow()
        XCTAssertNil(seam.closeWindow(at: now + 0.2))
    }
    
    func test_wake_window_extends_deadline() {
            let now = ProcessInfo.processInfo.systemUptime
            let normalDeadline = now + RouteSeam.Window.normal.duration
            let wakeDeadline = now + RouteSeam.Window.wake.duration

            // Start with normal window
            seam.noteEvent(at: now, window: .normal)
            XCTAssertEqual(seam.deadline, normalDeadline)

            // Extend with wake window
            seam.noteEvent(at: now + 0.1, window: .wake)
            XCTAssertEqual(seam.deadline, wakeDeadline)
        }

        // MARK: - S1: stale-generation callbacks

        func test_stale_generation_liveness_callback_is_ignored() {
            // The watchdog starts a proof under the generation current at start.
            let stamp = seam.advanceGeneration()
            // Mid-proof storm: device events bump the generation.
            seam.advanceGeneration()
            seam.advanceGeneration()
            // The callback lands with the old stamp. A stalled frame counter
            // under a stale generation is not a dead route — it is noise.
            XCTAssertEqual(
                seam.livenessVerdict(stamp: stamp, pipelineStillCurrent: true, statusActive: true, framesAdvanced: false, processProducingOutput: true),
                .superseded
            )
            // An "alive" verdict from the old generation is discarded too.
            XCTAssertEqual(
                seam.livenessVerdict(stamp: stamp, pipelineStillCurrent: true, statusActive: true, framesAdvanced: true, processProducingOutput: true),
                .superseded
            )
            // The proof under the current generation still speaks.
            XCTAssertEqual(
                seam.livenessVerdict(stamp: seam.generation, pipelineStillCurrent: true, statusActive: true, framesAdvanced: false, processProducingOutput: true),
                .dead
            )
        }

        func test_superseded_pipeline_is_ignored_at_current_generation() {
            // Current generation but the pipeline identity changed — stale proof.
            let stamp = seam.advanceGeneration()
            XCTAssertEqual(
                seam.livenessVerdict(stamp: stamp, pipelineStillCurrent: false, statusActive: true, framesAdvanced: false, processProducingOutput: true),
                .superseded
            )
            XCTAssertEqual(
                seam.livenessVerdict(stamp: stamp, pipelineStillCurrent: false, statusActive: true, framesAdvanced: true, processProducingOutput: true),
                .superseded
            )
            // Inactive routing status also supersedes.
            XCTAssertEqual(
                seam.livenessVerdict(stamp: stamp, pipelineStillCurrent: true, statusActive: false, framesAdvanced: false, processProducingOutput: true),
                .superseded
            )
        }

        // MARK: - S2: teardown waits for quiescence

        func test_teardown_cancels_pending_quiescent_commit() {
            let now = ProcessInfo.processInfo.systemUptime
            seam.noteEvent(at: now, window: .normal)
            let generationBefore = seam.generation
            // Teardown (stopRouting) cancels the pending window.
            seam.cancelWindow()
            // The timer still fires afterwards — it must commit nothing.
            XCTAssertNil(seam.closeWindow(at: now + 1.0))
            XCTAssertNil(seam.pendingWindow)
            XCTAssertNil(seam.deadline)
            XCTAssertEqual(seam.generation, generationBefore)
        }

        // MARK: - S2: kill criteria

        func test_storm_of_five_notifications_produces_one_commit() {
            let now = ProcessInfo.processInfo.systemUptime
            var commits = 0
            for i in 0..<5 {
                seam.noteEvent(at: now + Double(i) * 0.02, window: .normal)
            }
            // Timer attempts at each event's scheduled instant, plus after.
            for tick in stride(from: 0.0, through: 0.6, by: 0.02) {
                if seam.closeWindow(at: now + tick) != nil { commits += 1 }
            }
            XCTAssertEqual(commits, 1, "Exactly one commit from a five-event storm")
            XCTAssertEqual(seam.generation, 1, "One commit advances generation once")
        }

        func test_wake_that_settles_on_the_live_route_restarts_nothing() {
            let running = RouteSeam.RouteTuple(outputUID: "uid-bt", sampleRate: 44100, captureMode: .processTap)
            // A wake bumps the generation; the settled tuple is unchanged.
            seam.advanceGeneration()
            XCTAssertFalse(RouteSeam.commitNeedsRestart(settled: running, running: running, statusActive: true))
            // A settled change does restart.
            let moved = RouteSeam.RouteTuple(outputUID: "uid-speakers", sampleRate: 48000, captureMode: .processTap)
            XCTAssertTrue(RouteSeam.commitNeedsRestart(settled: moved, running: running, statusActive: true))
            // Nothing running restarts (idle or starting).
            XCTAssertTrue(RouteSeam.commitNeedsRestart(settled: running, running: nil, statusActive: false))
            // Unreadable settled tuple restarts.
            XCTAssertTrue(RouteSeam.commitNeedsRestart(settled: nil, running: running, statusActive: true))
        }

        // MARK: - Stress: rapid route flips converge

        func test_stress_250_rapid_flips_settle_on_one_route_and_generation() {
            struct LCG {
                var state: UInt64
                mutating func next() -> UInt64 {
                    state = state &* 6364136223846793005 &+ 1442695040888963407
                    return state >> 33
                }
                mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
                mutating func chance(_ percent: Int) -> Bool { below(100) < percent }
            }
            var rng = LCG(state: 0x5EA11)
            let outputs = [("uid-a", 44100.0), ("uid-b", 48000.0), ("uid-c", 96000.0)]
            var now = 1_000.0
            var settled = RouteSeam.RouteTuple(outputUID: outputs[0].0, sampleRate: outputs[0].1, captureMode: .processTap)
            var committed: RouteSeam.RouteTuple?
            var flips = 0
            var commits = 0
            var wakes = 0

            for _ in 0..<250 {
                let choice = outputs[rng.below(outputs.count)]
                settled = RouteSeam.RouteTuple(outputUID: choice.0, sampleRate: choice.1,
                                               captureMode: rng.chance(20) ? .halInput : .processTap)
                // Device event: new generation + a note into the coalescer.
                seam.advanceGeneration()
                let isWake = rng.chance(10)
                if isWake { wakes += 1 }
                seam.noteEvent(at: now, window: isWake ? .wake : .normal)
                flips += 1

                // Time advances 1–40 ms toward the next flip; a scheduled
                // commit attempt fires whenever the window has elapsed.
                now += Double(1 + rng.below(40)) / 1000.0
                if seam.isCommitDue(at: now), let window = seam.closeWindow(at: now) {
                    commits += 1
                    committed = settled
                    _ = window // silence unused
                }
            }
            // The storm ends: the last window elapses and commits once.
            now += 0.3
            if seam.closeWindow(at: now) != nil { commits += 1; committed = settled }

            XCTAssertEqual(flips, 250)
            XCTAssertGreaterThan(commits, 0, "At least one commit happened")
            XCTAssertLessThan(commits, flips / 2, "Coalescing collapsed the storm")
            XCTAssertEqual(committed?.outputUID, settled.outputUID)
            XCTAssertEqual(committed?.sampleRate, settled.sampleRate)
            XCTAssertEqual(committed?.captureMode, settled.captureMode)
            XCTAssertTrue(RouteSeam.matches(intent: settled, readBack: committed))
            XCTAssertEqual(seam.generation, UInt64(flips + commits), "One generation per event and per commit")
            XCTAssertNil(seam.pendingWindow, "No pending window after final commit")
            XCTAssertNil(seam.deadline)
            // Nothing from before the final flip is still current.
            XCTAssertFalse(seam.isCurrent(seam.generation - 1))
            XCTAssertTrue(seam.isCurrent(seam.generation))
        }
    }