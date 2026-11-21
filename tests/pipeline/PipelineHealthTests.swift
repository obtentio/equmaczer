// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// B3: the health assessor — matched rates are healthy, each
/// problem warns in priority order, and not-routing claims
/// nothing.
final class PipelineHealthTests: XCTestCase {
    private func facts(
        mode: CaptureMode? = .processTap,
        pipeline: Double? = 48_000,
        output: Double? = 48_000,
        input: Double? = nil,
        transport: Double? = 100,
        cpu: Double? = 12,
        failed: Int = 0
    ) -> PipelineHealthFacts {
        PipelineHealthFacts(
            activeMode: mode,
            pipelineRate: pipeline,
            outputRate: output,
            inputRate: input,
            transportPercent: transport,
            appCPUPercent: cpu,
            failedRouteCount: failed
        )
    }

    func testMatchedRatesAreHealthy() {
        let headline = PipelineHealth.headline(facts())
        XCTAssertTrue(headline.hasPrefix("Healthy"))
    }

    func testProcessingRateMismatchWarns() {
        let f = facts(pipeline: 48_000, output: 44_100)
        XCTAssertTrue(PipelineHealth.headline(f).contains("resamples"))
        let row = PipelineHealth.rows(f).first { $0.label == "Processing" }
        XCTAssertEqual(row?.level, .warn)
    }

    func testInputRateMismatchWarnsOnDriverPath() {
        let f = facts(mode: .sharedMemory, input: 44_100)
        XCTAssertTrue(PipelineHealth.headline(f).contains("resamples"))
        let row = PipelineHealth.rows(f).first { $0.label == "Input device" }
        XCTAssertEqual(row?.level, .warn)
    }

    func testStarvedTransportWarns() {
        let f = facts(transport: 22)
        XCTAssertTrue(PipelineHealth.headline(f).contains("starved"))
    }

    func testHighCPUIsNoted() {
        let f = facts(cpu: 140)
        XCTAssertTrue(PipelineHealth.headline(f).contains("working hard"))
    }

    func testFallbacksSurface() {
        let f = facts(failed: 1)
        XCTAssertTrue(PipelineHealth.headline(f).contains("fallback"))
        XCTAssertTrue(PipelineHealth.rows(f).contains { $0.label == "Route fallbacks" })
    }

    func testNotRoutingClaimsNothing() {
        let f = facts(mode: nil, pipeline: nil, output: nil, transport: nil, cpu: nil)
        XCTAssertEqual(PipelineHealth.headline(f), "Not routing — no health to report.")
    }

    func testStaleCaptureModeWithoutPipelineDoesNotClaimHealthy() {
        let f = facts(mode: .sharedMemory, pipeline: nil, output: 48_000, transport: nil, cpu: 0)
        XCTAssertEqual(PipelineHealth.headline(f), "Not routing — no health to report.")
    }

    func testUnmeasuredTransportDoesNotClaimHealthy() {
        XCTAssertTrue(PipelineHealth.headline(facts(transport: nil)).hasPrefix("Measuring"))
    }

    func testMismatchOutranksStarvation() {
        // The mismatch is the cause worth naming first.
        let f = facts(pipeline: 48_000, output: 44_100, transport: 10)
        XCTAssertTrue(PipelineHealth.headline(f).contains("resamples"))
    }

    func testTransportMath() {
        XCTAssertEqual(
            PipelineHealth.transportPercent(framesDelta: 48_000, seconds: 1, rate: 48_000),
            100
        )
        XCTAssertEqual(
            PipelineHealth.transportPercent(framesDelta: 24_000, seconds: 1, rate: 48_000),
            50
        )
        XCTAssertNil(PipelineHealth.transportPercent(framesDelta: 10, seconds: 0, rate: 48_000))
    }
}
