// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// The facts a health judgment is allowed to use (B3), assembled
/// live by the routing coordinator: rates read at snapshot time
/// (a device whose rate changes under a running chain is a health
/// event), the pipeline's own rate, and the session's fallback
/// history. Transport and app CPU are filled in by the pane, which
/// owns the sampling clocks.
struct PipelineHealthFacts: Equatable {
    var activeMode: CaptureMode?
    var pipelineRate: Double?
    var outputRate: Double?
    var inputRate: Double?
    var inputFramesReceived: UInt64 = 0
    var transportPercent: Double?
    var appCPUPercent: Double?
    var failedRouteCount: Int = 0
}

/// Pure health assessment: rows for the pane plus one headline.
/// The mismatch rule is the slice's reason to exist — macOS
/// resamples between devices running at different rates, the load
/// lands in the audio server (which an unprivileged app cannot
/// read, so the panel shows the cause, never an invented figure
/// for it), and a sustained mismatch is the shape behind the
/// call-freeze incident on record.
enum PipelineHealth {
    enum Level: Equatable {
        case ok
        case warn
    }

    struct Row: Equatable {
        var label: String
        var value: String
        var level: Level
    }

    static func transportPercent(
        framesDelta: UInt64,
        seconds: Double,
        rate: Double
    ) -> Double? {
        guard seconds > 0, rate > 0 else { return nil }
        return Double(framesDelta) / seconds / rate * 100
    }

    private static func ratesMismatch(_ a: Double?, _ b: Double?) -> Bool {
        guard let a, let b else { return false }
        return abs(a - b) > 1
    }

    private static func hz(_ rate: Double) -> String {
        "\(Int(rate.rounded())) Hz"
    }

    static func rows(_ facts: PipelineHealthFacts) -> [Row] {
        var rows: [Row] = []
        if let output = facts.outputRate {
            rows.append(Row(label: "Output device", value: hz(output), level: .ok))
        }
        if let input = facts.inputRate {
            let mismatch = ratesMismatch(input, facts.outputRate)
            rows.append(Row(
                label: "Input device",
                value: hz(input),
                level: mismatch ? .warn : .ok
            ))
        }
        if let pipeline = facts.pipelineRate {
            let mismatch = ratesMismatch(pipeline, facts.outputRate)
            rows.append(Row(
                label: "Processing",
                value: hz(pipeline),
                level: mismatch ? .warn : .ok
            ))
        }
        if let transport = facts.transportPercent {
            rows.append(Row(
                label: "Transport",
                value: String(format: "%.0f%% of rate", transport),
                level: transport < 50 ? .warn : .ok
            ))
        }
        if let cpu = facts.appCPUPercent {
            rows.append(Row(
                label: "This app's CPU",
                value: String(format: "%.0f%% of one core", cpu),
                level: cpu > 80 ? .warn : .ok
            ))
        }
        if facts.failedRouteCount > 0 {
            rows.append(Row(
                label: "Route fallbacks",
                value: "\(facts.failedRouteCount) this session",
                level: .warn
            ))
        }
        return rows
    }

    static func headline(_ facts: PipelineHealthFacts) -> String {
        guard facts.activeMode != nil, facts.pipelineRate != nil else {
            return "Not routing — no health to report."
        }
        if ratesMismatch(facts.pipelineRate, facts.outputRate)
            || ratesMismatch(facts.inputRate, facts.outputRate) {
            return "Sample rates differ — macOS resamples between them, and the load lands in the audio server. A sustained mismatch is the shape behind the call freeze on record. Rates are set per device in Audio MIDI Setup."
        }
        if let transport = facts.transportPercent, transport < 50 {
            return "Transport is starved — frames are arriving at \(String(format: "%.0f", transport))% of the rate the device promises."
        }
        if let cpu = facts.appCPUPercent, cpu > 80 {
            return "This app is working hard — \(String(format: "%.0f", cpu))% of one core."
        }
        if facts.failedRouteCount > 0 {
            return "Routing is up, after a fallback this session — the notice above says which route gave up."
        }
        guard facts.outputRate != nil, facts.transportPercent != nil, facts.appCPUPercent != nil else {
            return "Measuring routing health — waiting for transport and load samples."
        }
        return "Healthy — rates matched, transport full, load normal."
    }
}
