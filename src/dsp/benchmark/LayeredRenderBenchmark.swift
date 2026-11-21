import Darwin
import Foundation

/// In-process stress measurement; excludes real HAL scheduling and device latency.
enum LayeredRenderBenchmark {
    static func run() -> Bool {
        let frames: UInt32 = 64
        let rate = 96000.0
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: frames)
        context.configureLoudness(sampleRate: rate)
        context.configureLimiters(sampleRate: rate)
        context.setMetersEnabled(true)
        let coefficients = (0..<64).map { i in
            SVFMath.calculateDecrampedSVF(type: .parametric, sampleRate: rate,
                frequency: 30 * pow(20000.0 / 30, Double(i) / 63), q: 1.41,
                gain: i.isMultiple(of: 2) ? 0.5 : -0.5)
        }
        for chain in context.leftEQChains + context.rightEQChains {
            chain.stageFullUpdate(coefficients: coefficients, bypassFlags: Array(repeating: false, count: 64),
                activeBandCount: 64, layerBypass: false)
        }
        let signal = (0..<Int(frames)).map { Float(sin(2 * .pi * 1000 * Double($0) / rate) * 0.01) }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticksToUs = Double(timebase.numer) / Double(timebase.denom) / 1000
        var timings = [Double]()
        timings.reserveCapacity(2000)
        for iteration in 0..<2100 {
            let start = mach_absolute_time()
            signal.withUnsafeBufferPointer { input in
                for ring in context.ringBuffers { _ = ring.write(input.baseAddress!, count: Int(frames)) }
            }
            _ = context.provideFrames(frameCount: frames)
            context.measureLoudnessIn(frameCount: frames)
            context.processEQ(frameCount: frames)
            context.measureLoudnessOut(frameCount: frames)
            if iteration >= 100 { timings.append(Double(mach_absolute_time() - start) * ticksToUs) }
        }
        timings.sort()
        let p50 = timings[timings.count / 2]
        let p99 = timings[Int(Double(timings.count - 1) * 0.99)]
        let deadline = Double(frames) / rate * 1_000_000
        print(String(format: "Stereo × 4 layers × 64 bands, limiter + loudness/spectrum + ring transport, 64 frames @ 96 kHz: p50 %.2f µs, p99 %.2f µs, deadline %.2f µs. Excludes HAL scheduling/device latency.", p50, p99, deadline))
        return p99 < deadline
    }
}
