// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// BS.1770 loudness tests. Anchors were computed independently in
/// Python (scipy) from the published 48 kHz coefficients before the
/// Swift port existed: the K-filter design must reproduce the
/// published coefficients at 48 kHz, and sine loudness must match
/// the reference values.
final class KWeightingTests: XCTestCase {
    func testCoefficientsAt48kMatchThePublishedStandard() {
        let coeffs = KWeighting.coefficients(sampleRate: 48000)
        // ITU-R BS.1770 published 48 kHz coefficients.
        XCTAssertEqual(coeffs.stage1.b0, 1.53512485958697, accuracy: 1e-6)
        XCTAssertEqual(coeffs.stage1.b1, -2.69169618940638, accuracy: 1e-6)
        XCTAssertEqual(coeffs.stage1.b2, 1.19839281085285, accuracy: 1e-6)
        XCTAssertEqual(coeffs.stage1.a1, -1.69065929318241, accuracy: 1e-6)
        XCTAssertEqual(coeffs.stage1.a2, 0.73248077421585, accuracy: 1e-6)
        XCTAssertEqual(coeffs.stage2.b0, 1.0, accuracy: 1e-9)
        XCTAssertEqual(coeffs.stage2.b1, -2.0, accuracy: 1e-9)
        XCTAssertEqual(coeffs.stage2.b2, 1.0, accuracy: 1e-9)
        XCTAssertEqual(coeffs.stage2.a1, -1.99004745483398, accuracy: 1e-6)
        XCTAssertEqual(coeffs.stage2.a2, 0.99007225036621, accuracy: 1e-6)
    }
}

final class LoudnessProbeTests: XCTestCase {
    /// Feeds a stereo sine through a probe and returns the gated
    /// integrated loudness of the drained blocks.
    private func integratedLUFS(frequency: Double, amplitudeDB: Double, seconds: Double = 10) -> Double? {
        let sampleRate = 48000.0
        let probe = LoudnessProbe()
        probe.configure(sampleRate: sampleRate)
        let amplitude = pow(10.0, amplitudeDB / 20.0)
        let totalFrames = Int(sampleRate * seconds)
        let chunk = 1024
        let left = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
        defer { left.deallocate(); right.deallocate() }
        var frame = 0
        while frame < totalFrames {
            let count = min(chunk, totalFrames - frame)
            for i in 0..<count {
                let sample = Float(amplitude * sin(2.0 * Double.pi * frequency * Double(frame + i) / sampleRate))
                left[i] = sample
                right[i] = sample
            }
            probe.feed(buffers: [UnsafePointer(left), UnsafePointer(right)], frameCount: count)
            frame += count
        }
        return LoudnessMeter.gatedIntegratedLUFS(blockZ: probe.drainBlocks())
    }

    func testFullScale1kHzSineMeasuresZeroLUFS() {
        // The BS.1770 calibration anchor: a 1 kHz stereo sine at
        // 0 dBFS measures ≈ 0 LUFS (independently computed: +0.007).
        XCTAssertEqual(integratedLUFS(frequency: 1000, amplitudeDB: 0) ?? .nan, 0.007, accuracy: 0.05)
    }

    func testSineLoudnessAnchors() {
        XCTAssertEqual(integratedLUFS(frequency: 1000, amplitudeDB: -20) ?? .nan, -19.99, accuracy: 0.05)
        XCTAssertEqual(integratedLUFS(frequency: 100, amplitudeDB: -20) ?? .nan, -21.82, accuracy: 0.15)
        XCTAssertEqual(integratedLUFS(frequency: 10000, amplitudeDB: -20) ?? .nan, -16.65, accuracy: 0.15)
    }

    func testSilenceProducesNoReading() {
        let probe = LoudnessProbe()
        probe.configure(sampleRate: 48000)
        let zeros = UnsafeMutablePointer<Float>.allocate(capacity: 1024)
        zeros.initialize(repeating: 0, count: 1024)
        defer { zeros.deallocate() }
        for _ in 0..<200 {
            probe.feed(buffers: [UnsafePointer(zeros), UnsafePointer(zeros)], frameCount: 1024)
        }
        XCTAssertNil(LoudnessMeter.gatedIntegratedLUFS(blockZ: probe.drainBlocks()))
    }
}

final class LoudnessGatingTests: XCTestCase {
    private func z(forLUFS lufs: Double) -> Double {
        pow(10.0, (lufs + 0.691) / 10.0)
    }

    func testAbsoluteGateDropsNearSilence() {
        var blocks = [Double](repeating: z(forLUFS: -23), count: 10)
        blocks.append(contentsOf: [Double](repeating: z(forLUFS: -75), count: 1000))
        XCTAssertEqual(LoudnessMeter.gatedIntegratedLUFS(blockZ: blocks) ?? .nan, -23, accuracy: 0.05)
    }

    func testRelativeGateDropsQuietPassages() {
        var blocks = [Double](repeating: z(forLUFS: -23), count: 100)
        blocks.append(contentsOf: [Double](repeating: z(forLUFS: -53), count: 100))
        // Ungated ≈ −26 LUFS → relative threshold −36 → the −53
        // blocks are gated out and the result returns to −23.
        XCTAssertEqual(LoudnessMeter.gatedIntegratedLUFS(blockZ: blocks) ?? .nan, -23, accuracy: 0.05)
    }

    func testEmptyAndZeroEnergyGiveNoReading() {
        XCTAssertNil(LoudnessMeter.gatedIntegratedLUFS(blockZ: []))
        XCTAssertNil(LoudnessMeter.gatedIntegratedLUFS(blockZ: [0, 0, 0]))
    }
}

final class BypassDeltaTests: XCTestCase {
    private func z(forLUFS lufs: Double) -> Double {
        pow(10.0, (lufs + 0.691) / 10.0)
    }

    func testDeltaIsThePairedLoudnessDifference() {
        let pre = [Double](repeating: z(forLUFS: -20), count: 40)
        let post = [Double](repeating: z(forLUFS: -17.5), count: 40)
        XCTAssertEqual(LoudnessMeter.pairedDeltaDB(pre: pre, post: post) ?? .nan, 2.5, accuracy: 0.02)
    }

    func testDeltaNeedsEnoughProgramme() {
        let pre = [Double](repeating: z(forLUFS: -20), count: 10)
        let post = [Double](repeating: z(forLUFS: -17.5), count: 10)
        XCTAssertNil(LoudnessMeter.pairedDeltaDB(pre: pre, post: post))
    }

    func testDeltaIgnoresQuietPairs() {
        let pre = [Double](repeating: z(forLUFS: -65), count: 100)
        let post = [Double](repeating: z(forLUFS: -62.5), count: 100)
        XCTAssertNil(LoudnessMeter.pairedDeltaDB(pre: pre, post: post))
    }

    /// End to end: two probes fed the same tone at different levels
    /// must produce that level difference as the delta.
    func testDeltaFromProbes() {
        let sampleRate = 48000.0
        let preProbe = LoudnessProbe()
        let postProbe = LoudnessProbe()
        preProbe.configure(sampleRate: sampleRate)
        postProbe.configure(sampleRate: sampleRate)
        let chunk = 1024
        let totalFrames = Int(sampleRate * 4)
        let bufA = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
        let bufB = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
        defer { bufA.deallocate(); bufB.deallocate() }
        let ampA = pow(10.0, -20.0 / 20.0)
        let ampB = ampA * pow(10.0, 2.5 / 20.0)
        var frame = 0
        while frame < totalFrames {
            let count = min(chunk, totalFrames - frame)
            for i in 0..<count {
                let phase = 2.0 * Double.pi * 1000.0 * Double(frame + i) / sampleRate
                bufA[i] = Float(ampA * sin(phase))
                bufB[i] = Float(ampB * sin(phase))
            }
            preProbe.feed(buffers: [UnsafePointer(bufA), UnsafePointer(bufA)], frameCount: count)
            postProbe.feed(buffers: [UnsafePointer(bufB), UnsafePointer(bufB)], frameCount: count)
            frame += count
        }
        let delta = LoudnessMeter.pairedDeltaDB(
            pre: preProbe.drainBlocks(),
            post: postProbe.drainBlocks()
        )
        XCTAssertEqual(delta ?? .nan, 2.5, accuracy: 0.05)
    }
}

/// The bypass-drift fix: a restage clears the paired histories (no
/// decaying blend of the old configuration) and shifts the held
/// delta by the restage's preamp change until fresh pairs refine it.
final class BypassDeltaRestageTests: XCTestCase {
    private func z(forLUFS lufs: Double) -> Double {
        pow(10.0, (lufs + 0.691) / 10.0)
    }

    private func convergedMeter(deltaDB: Double) -> LoudnessMeter {
        let meter = LoudnessMeter()
        let pre = [Double](repeating: z(forLUFS: -20), count: 40)
        let post = [Double](repeating: z(forLUFS: -20 + deltaDB), count: 40)
        meter.ingest(display: [], pre: pre, post: post)
        XCTAssertEqual(meter.bypassDeltaDB ?? .nan, deltaDB, accuracy: 0.02)
        return meter
    }

    func testRestageShiftsTheHeldDeltaByThePreampChange() {
        let meter = convergedMeter(deltaDB: -2.5)
        meter.restage(preampDeltaDB: -8, absoluteSeedDB: -11)
        XCTAssertEqual(meter.bypassDeltaDB ?? .nan, -10.5, accuracy: 0.001)
    }

    func testRestageClearsThePairedHistory() {
        let meter = convergedMeter(deltaDB: -2.5)
        meter.restage(preampDeltaDB: -8, absoluteSeedDB: -11)
        // A few fresh pairs are not enough to refine: the seed holds.
        let pre = [Double](repeating: z(forLUFS: -20), count: 10)
        let post = [Double](repeating: z(forLUFS: -29), count: 10)
        meter.ingest(display: [], pre: pre, post: post)
        XCTAssertEqual(meter.bypassDeltaDB ?? .nan, -10.5, accuracy: 0.001)
    }

    func testFreshPairsRefineTheSeed() {
        let meter = convergedMeter(deltaDB: -2.5)
        meter.restage(preampDeltaDB: -8, absoluteSeedDB: -11)
        let pre = [Double](repeating: z(forLUFS: -20), count: 40)
        let post = [Double](repeating: z(forLUFS: -29), count: 40)
        meter.ingest(display: [], pre: pre, post: post)
        XCTAssertEqual(meter.bypassDeltaDB ?? .nan, -9, accuracy: 0.02)
    }

    func testUnconvergedRestageSeedsFromThePreamp() {
        let meter = LoudnessMeter()
        meter.restage(preampDeltaDB: 0, absoluteSeedDB: -6)
        XCTAssertEqual(meter.bypassDeltaDB ?? .nan, -6, accuracy: 0.001)
    }

    func testSeedIsClamped() {
        let meter = convergedMeter(deltaDB: -11)
        meter.restage(preampDeltaDB: -8, absoluteSeedDB: -19)
        XCTAssertEqual(meter.bypassDeltaDB ?? .nan, -12, accuracy: 0.001)
    }
}
