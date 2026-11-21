// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// True-peak limiter behaviour tests, adapted from the kill criteria in the
/// 2026-11-12 design consult: the attack must ramp across the lookahead
/// (never step), re-triggers mid-ramp must stay covered, sustained bass must
/// not be waveshaped by gain chatter, and hold/release must scale with the
/// sample rate (80 ms time constant at every rate).
final class TruePeakLimiterTests: XCTestCase {

    private let ceilingDBTP: Float = -1.0

    private func makeLimiter(sampleRate: Double = 48000) -> TruePeakLimiter {
        let limiter = TruePeakLimiter(ceilingDBTP: ceilingDBTP)
        limiter.configure(sampleRate: sampleRate)
        return limiter
    }

    private func run(_ limiter: TruePeakLimiter, _ signal: [Float]) -> [Float] {
        var buffer = signal
        buffer.withUnsafeMutableBufferPointer { ptr in
            limiter.processInPlace(buffer: ptr.baseAddress!, frameCount: ptr.count)
        }
        return buffer
    }

    /// The gain trajectory must descend in bounded steps, never one full
    /// step. Probed with a slow input ramp (0 → 2x ceiling over 400 samples):
    /// a step input is the wrong probe — the ramp is designed to complete
    /// inside the lookahead, while the delayed output is still silent, and a
    /// step edge makes the detector ring. On a ramp the requirement deepens
    /// gradually, so the trajectory is observable at the output.
    func testAttackRampsAcrossTheLookahead() {
        let limiter = makeLimiter()
        let ceiling = limiter.ceilingLinear
        var signal = [Float](repeating: 0, count: 100)
        signal += (0..<400).map { Float($0) / 400.0 * 2.0 }
        signal += [Float](repeating: 2.0, count: 400)
        let out = run(limiter, signal)

        let targetGain = ceiling / 2.0
        let maxStep = (1.0 - targetGain) / 6.0 + 0.04

        var previous: Float = 1.0
        var sawDescent = false
        for i in 12..<signal.count where signal[i - 12] >= 0.5 {
            let gain = out[i] / signal[i - 12]
            if gain < 0.999 { sawDescent = true }
            if sawDescent {
                XCTAssertLessThanOrEqual(
                    previous - gain, maxStep,
                    "gain fell \(previous - gain) in one sample at \(i); the attack must ramp")
            }
            previous = gain
        }
        XCTAssertTrue(sawDescent)
        XCTAssertEqual(previous, targetGain, accuracy: 0.03,
                       "gain must settle at the required depth for a 2x-ceiling signal")
        for i in 200..<signal.count {
            XCTAssertLessThanOrEqual(abs(out[i]), ceiling * 1.03)
        }
    }

    /// A second, deeper impulse arriving mid-ramp must not escape: the
    /// steepest-slope rule keeps the first peak covered while descending
    /// further for the second.
    func testDoublePulseRetriggerStaysUnderCeiling() {
        for separation in 1...5 {
            let limiter = makeLimiter()
            let ceiling = limiter.ceilingLinear
            var signal = [Float](repeating: 0, count: 400)
            signal[100] = ceiling * pow(10.0, 2.0 / 20.0)
            signal[100 + separation] = ceiling * pow(10.0, 8.0 / 20.0)
            let out = run(limiter, signal)
            XCTAssertLessThanOrEqual(
                abs(out[112]), ceiling * 1.03,
                "first impulse escaped at separation \(separation)")
            XCTAssertLessThanOrEqual(
                abs(out[112 + separation]), ceiling * 1.03,
                "second impulse escaped at separation \(separation)")
        }
    }

    /// fs/4 cosine at +6 dB over the ceiling: an independent detector pass
    /// over the output must still read at (or negligibly above) the ceiling.
    func testCeilingHoldsOnFsQuarterCosine() {
        let limiter = makeLimiter()
        let ceiling = limiter.ceilingLinear
        let amplitude = ceiling * pow(10.0, 6.0 / 20.0)
        let signal = (0..<4800).map { n in
            amplitude * Float(cos(Double.pi / 2.0 * Double(n) + Double.pi / 4.0))
        }
        let out = run(limiter, signal)
        let meter = TruePeakDetector()
        var peak: Float = 0
        for sample in out { peak = max(peak, meter.processSample(sample)) }
        XCTAssertLessThanOrEqual(peak, ceiling * 1.02)
    }

    /// Sustained bass 3 dB over the ceiling: with a 10 ms hold and an 80 ms
    /// release the gain must ride, not chatter — steady-state THD stays low.
    func testSustainedBassTHD() {
        for (frequency, threshold) in [(50.0, 0.0035), (100.0, 0.0015)] {
            let limiter = makeLimiter()
            let ceiling = limiter.ceilingLinear
            let amplitude = ceiling * pow(10.0, 3.0 / 20.0)
            let count = 48000 * 2
            let signal = (0..<count).map { n in
                amplitude * Float(sin(2.0 * Double.pi * frequency * Double(n) / 48000.0))
            }
            let out = run(limiter, signal)
            // Analyse the settled second half over whole cycles.
            let start = 4800
            let cycles = Int((Double(count - start) * frequency / 48000.0).rounded(.down))
            let window = cycles * Int(48000.0 / frequency)
            func component(_ f: Double) -> Double {
                var re = 0.0, im = 0.0
                for i in 0..<window {
                    let phase = 2.0 * Double.pi * f * Double(i) / 48000.0
                    re += Double(out[start + i]) * cos(phase)
                    im -= Double(out[start + i]) * sin(phase)
                }
                return sqrt(re * re + im * im)
            }
            let fundamental = component(frequency)
            var harmonicPower = 0.0
            for h in 2...10 {
                let c = component(frequency * Double(h))
                harmonicPower += c * c
            }
            let thd = sqrt(harmonicPower) / fundamental
            XCTAssertLessThan(thd, threshold,
                              "THD at \(frequency) Hz is \(thd); gain is chattering on bass")
        }
    }

    /// Release is an 80 ms time constant at ANY sample rate: recovery from a
    /// deep cut to 0.95 must take ~4x as many samples at 192 kHz as at 48 kHz
    /// (the old fixed per-sample coefficient recovered in equal samples).
    func testReleaseScalesWithSampleRate() {
        func recoverySamples(sampleRate: Double) -> Int {
            let limiter = makeLimiter(sampleRate: sampleRate)
            let burst = Int(sampleRate * 0.01)
            var signal = [Float](repeating: 2.0, count: burst)
            signal += [Float](repeating: 0.05, count: Int(sampleRate * 1.5))
            let out = run(limiter, signal)
            for i in (burst + 12)..<out.count where signal[i - 12] == 0.05 {
                if out[i] / 0.05 >= 0.95 { return i - burst }
            }
            return Int.max
        }
        let at48 = recoverySamples(sampleRate: 48000)
        let at192 = recoverySamples(sampleRate: 192000)
        XCTAssertGreaterThan(at48, 4000, "release recovered implausibly fast at 48 kHz")
        XCTAssertLessThan(at48, 16000, "release recovered implausibly slowly at 48 kHz")
        let ratio = Double(at192) / Double(at48)
        XCTAssertGreaterThan(ratio, 3.2, "release did not scale with sample rate (ratio \(ratio))")
        XCTAssertLessThan(ratio, 4.8, "release over-scaled with sample rate (ratio \(ratio))")
    }

    // MARK: - Stereo linking (Linked channel mode only)

    private func sine(amplitude: Float, frames: Int, sampleRate: Double = 48000, frequency: Double = 1000) -> [Float] {
        (0..<frames).map { amplitude * Float(sin(2 * Double.pi * frequency * Double($0) / sampleRate)) }
    }

    private func peak(of signal: ArraySlice<Float>) -> Float {
        signal.map { abs($0) }.max() ?? 0
    }

    /// Linked mode: a hot left channel pulls the quiet right channel
    /// down by the same gain — limiting never shifts the stereo image.
    func testLinkedPairSharesOneGainTrajectory() {
        let left = makeLimiter()
        let right = makeLimiter()
        let frames = 9600
        var leftSignal = sine(amplitude: 1.6, frames: frames)
        var rightSignal = sine(amplitude: 0.2, frames: frames)

        leftSignal.withUnsafeMutableBufferPointer { leftPtr in
            rightSignal.withUnsafeMutableBufferPointer { rightPtr in
                left.processLinkedPairInPlace(
                    other: right,
                    leftBuffer: leftPtr.baseAddress!,
                    rightBuffer: rightPtr.baseAddress!,
                    frameCount: frames
                )
            }
        }

        let ceiling = left.ceilingLinear
        let tail = 4800..<frames
        XCTAssertLessThanOrEqual(peak(of: leftSignal[tail]), ceiling * 1.02,
                                 "linked left channel must respect the ceiling")
        // Shared gain ≈ ceiling / 1.6 ≈ 0.557, so the 0.2 right channel
        // peaks near 0.111 — clearly ducked, in step with the left.
        let rightPeak = peak(of: rightSignal[tail])
        XCTAssertGreaterThan(rightPeak, 0.09, "right channel under-ducked: gain not shared")
        XCTAssertLessThan(rightPeak, 0.135, "right channel over-ducked: gain not the shared trajectory")
    }

    /// The independent path (Stereo mode): a quiet channel is untouched
    /// by a hot one — asymmetric compensation is never ducked.
    func testIndependentLimitersDoNotShareGain() {
        let left = makeLimiter()
        let right = makeLimiter()
        let frames = 9600
        _ = run(left, sine(amplitude: 1.6, frames: frames))
        let outRight = run(right, sine(amplitude: 0.2, frames: frames))
        XCTAssertEqual(peak(of: outRight[4800..<frames]), 0.2, accuracy: 0.01)
    }

    // MARK: - Gain reduction metering

    func testGainReductionReportsThePeakCutAndClears() {
        let limiter = makeLimiter()
        _ = run(limiter, sine(amplitude: 1.6, frames: 9600))
        // A 1.6x sine against a −1 dBTP ceiling (≈0.891) needs the
        // gain down near 0.56, about −5.1 dB.
        let gr = limiter.consumeMaxGainReductionDB()
        XCTAssertEqual(gr, 5.1, accuracy: 1.0)
        // Consumed: a second read with no new limiting is zero.
        XCTAssertEqual(limiter.consumeMaxGainReductionDB(), 0, accuracy: 0.0001)
    }

    func testGainReductionIsZeroBelowTheCeiling() {
        let limiter = makeLimiter()
        _ = run(limiter, sine(amplitude: 0.2, frames: 9600))
        XCTAssertEqual(limiter.consumeMaxGainReductionDB(), 0, accuracy: 0.0001)
    }

    func testLinkedPairReportsOnTheDrivingLimiter() {
        let left = makeLimiter()
        let right = makeLimiter()
        var leftBuffer = sine(amplitude: 1.6, frames: 9600)
        var rightBuffer = sine(amplitude: 0.2, frames: 9600)
        let frames = leftBuffer.count
        leftBuffer.withUnsafeMutableBufferPointer { lPtr in
            rightBuffer.withUnsafeMutableBufferPointer { rPtr in
                left.processLinkedPairInPlace(
                    other: right,
                    leftBuffer: lPtr.baseAddress!,
                    rightBuffer: rPtr.baseAddress!,
                    frameCount: frames
                )
            }
        }
        XCTAssertGreaterThan(left.consumeMaxGainReductionDB(), 3)
    }
}
