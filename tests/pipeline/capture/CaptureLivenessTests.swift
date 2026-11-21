// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// Capture liveness tests: the route planner's ordering rules, its
/// pinned equivalence with `CaptureModePolicy` (first choice), a
/// 500-walk transition fuzz over the planner's state machine, and
/// the frame counter the watchdog samples.
///
/// The fuzz drives the *decision* layer — the part that picks where
/// audio comes from after every device/mode/capability flip — with
/// simulated live/dead routes. Its invariant is the product rule:
/// a session must never end active on a route that produces nothing,
/// and must only give up when no live route exists.
final class CaptureRoutePlannerTests: XCTestCase {

    func testManualModeOnlyEverHALInput() {
        for preference in CaptureMode.allCases {
            XCTAssertEqual(
                CaptureRoutePlanner.orderedCandidates(
                    preference: preference, isManualMode: true, supportsSharedMemory: true
                ),
                [.halInput]
            )
        }
    }

    func testTapIsPreferenceOnlyNeverAFallback() {
        let candidates = CaptureRoutePlanner.orderedCandidates(
            preference: .sharedMemory, isManualMode: false, supportsSharedMemory: true
        )
        XCTAssertFalse(candidates.contains(.processTap))
        XCTAssertEqual(candidates, [.sharedMemory, .halInput])
    }

    func testTapPreferenceLeadsThenFallsBack() {
        XCTAssertEqual(
            CaptureRoutePlanner.orderedCandidates(
                preference: .processTap, isManualMode: false, supportsSharedMemory: true
            ),
            [.processTap, .sharedMemory, .halInput]
        )
        XCTAssertEqual(
            CaptureRoutePlanner.orderedCandidates(
                preference: .processTap, isManualMode: false, supportsSharedMemory: false
            ),
            [.processTap, .halInput]
        )
    }

    func testIncapableSharedMemoryPreferenceResolvesToHAL() {
        XCTAssertEqual(
            CaptureRoutePlanner.orderedCandidates(
                preference: .sharedMemory, isManualMode: false, supportsSharedMemory: false
            ),
            [.halInput]
        )
    }

    func testNextCandidateSkipsFailedAndExhausts() {
        XCTAssertEqual(
            CaptureRoutePlanner.nextCandidate(
                after: [.processTap], preference: .processTap,
                isManualMode: false, supportsSharedMemory: true
            ),
            .sharedMemory
        )
        XCTAssertNil(
            CaptureRoutePlanner.nextCandidate(
                after: [.processTap, .sharedMemory, .halInput], preference: .processTap,
                isManualMode: false, supportsSharedMemory: true
            )
        )
    }

    /// The planner's first candidate must equal the policy's resolved
    /// mode for every input combination — the two decision layers
    /// cannot drift apart.
    func testPlannerFirstCandidateMatchesPolicyEverywhere() {
        for preference in CaptureMode.allCases {
            for manual in [false, true] {
                for shared in [false, true] {
                    let decision = CaptureModePolicy.determineMode(
                        preference: preference, isManualMode: manual, supportsSharedMemory: shared
                    )
                    let resolved: CaptureMode
                    switch decision {
                    case .useMode(let mode): resolved = mode
                    case .fallbackToHALInput: resolved = .halInput
                    }
                    let first = CaptureRoutePlanner.orderedCandidates(
                        preference: preference, isManualMode: manual, supportsSharedMemory: shared
                    ).first
                    XCTAssertEqual(
                        first, resolved,
                        "pref=\(preference) manual=\(manual) shared=\(shared)"
                    )
                }
            }
        }
    }
}

final class TransitionFuzzTests: XCTestCase {
    /// Deterministic RNG (LCG) so the fuzz is identical on every run.
    private struct LCG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
        mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
        mutating func chance(_ percent: Int) -> Bool { below(100) < percent }
    }

    func testFiveHundredTransitionWalksNeverEndSilent() {
        var rng = LCG(state: 0x2F6E2B1)
        var totalAttempts = 0
        var giveUps = 0

        for walk in 0..<500 {
            var preference = CaptureMode.allCases[rng.below(3)]
            var manual = rng.chance(25)
            var sharedCapable = rng.chance(50)
            // Which routes would actually flow if tried, this segment.
            var liveModes = Set(CaptureMode.allCases.filter { _ in rng.chance(60) })

            for segment in 0..<6 {
                // One routing session: try candidates until one flows
                // or the planner gives up — the coordinator's logic.
                var failed: Set<CaptureMode> = []
                var attempts: [CaptureMode] = []
                var landed: CaptureMode? = CaptureRoutePlanner.nextCandidate(
                    after: failed, preference: preference,
                    isManualMode: manual, supportsSharedMemory: sharedCapable
                )
                while let mode = landed, !liveModes.contains(mode) {
                    failed.insert(mode)
                    attempts.append(mode)
                    landed = CaptureRoutePlanner.nextCandidate(
                        after: failed, preference: preference,
                        isManualMode: manual, supportsSharedMemory: sharedCapable
                    )
                }
                totalAttempts += attempts.count

                // Invariants — the product rule, after every flip.
                XCTAssertEqual(
                    attempts.count, Set(attempts).count,
                    "walk \(walk) segment \(segment): a route was retried within one session"
                )
                if let landed {
                    XCTAssertTrue(
                        liveModes.contains(landed),
                        "walk \(walk) segment \(segment): session ended ACTIVE on dead route \(landed)"
                    )
                } else {
                    giveUps += 1
                    let candidates = CaptureRoutePlanner.orderedCandidates(
                        preference: preference, isManualMode: manual,
                        supportsSharedMemory: sharedCapable
                    )
                    XCTAssertTrue(
                        candidates.allSatisfy { !liveModes.contains($0) },
                        "walk \(walk) segment \(segment): gave up while a live route existed"
                    )
                }

                // A transition: device, capability, preference, or the
                // world's liveness changes; the session resets.
                if rng.chance(33) { sharedCapable.toggle() }
                if rng.chance(33) { liveModes = Set(CaptureMode.allCases.filter { _ in rng.chance(60) }) }
                if rng.chance(25) { preference = CaptureMode.allCases[rng.below(3)] }
                if rng.chance(15) { manual.toggle() }
            }
        }

        // The fuzz must actually have exercised failure and give-up
        // paths, not just happy routes.
        XCTAssertGreaterThan(totalAttempts, 500)
        XCTAssertGreaterThan(giveUps, 0)
    }
}

final class InputFrameCounterTests: XCTestCase {
    func testCounterAccumulatesRealFramesOnly() {
        let context = RenderCallbackContext(
            inputHALUnit: nil,
            channelCount: 2,
            maxFrameCount: 512,
            ringBufferCapacity: 4096
        )
        XCTAssertEqual(context.inputFramesReceived, 0)

        context.noteInputFrames(256)
        context.noteInputFrames(0)
        context.noteInputFrames(-8)
        XCTAssertEqual(context.inputFramesReceived, 256)

        context.writeToRingBuffers(frameCount: 128)
        XCTAssertEqual(context.inputFramesReceived, 384)
    }
}
