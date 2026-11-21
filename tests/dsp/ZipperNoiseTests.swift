// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// D5: the drag path must be click-free. A band's coefficients
/// are swapped between callbacks with the SVF state carried
/// across, so even a 24 dB mid-stream swing — the worst drag
/// case — must not produce a sample discontinuity beyond what
/// the responses themselves explain. The yardstick is the
/// settled max slope of chains rendering each endpoint
/// coefficient set from the start.
final class ZipperNoiseTests: XCTestCase {
    private let sampleRate: Double = 48_000
    private let blockSize = 512
    private let blockCount = 12

    private func coefficients(gain: Float) -> SVFCoefficients {
        SVFMath.calculateDecrampedSVF(
            type: .parametric,
            sampleRate: sampleRate,
            frequency: 1_000,
            q: 1.41,
            gain: Double(gain)
        )
    }

    /// Renders a 1 kHz sine through a one-band chain starting
    /// at `startGain`; when `swing` is set, that block boundary
    /// stages a coefficient change to the swing's gain.
    private func render(startGain: Float, swing: (block: Int, gain: Float)?) -> [Float] {
        let chain = EQChain(maxFrameCount: UInt32(blockSize))
        chain.stageFullUpdate(
            coefficients: [coefficients(gain: startGain)],
            bypassFlags: [false],
            activeBandCount: 1,
            layerBypass: false
        )
        var output: [Float] = []
        output.reserveCapacity(blockSize * blockCount)
        var block: [Float] = []
        block.reserveCapacity(blockSize)
        for blockIndex in 0..<blockCount {
            if let swing, swing.block == blockIndex {
                chain.stageBandUpdate(index: 0, coefficients: coefficients(gain: swing.gain), bypass: false)
            }
            block.removeAll(keepingCapacity: true)
            for frame in 0..<blockSize {
                let n = blockIndex * blockSize + frame
                block.append(Float(0.25 * sin(2.0 * Double.pi * 1_000.0 * Double(n) / sampleRate)))
            }
            block.withUnsafeMutableBufferPointer { pointer in
                chain.process(buffer: pointer.baseAddress!, frameCount: UInt32(blockSize))
            }
            output.append(contentsOf: block)
        }
        return output
    }

    private func maxStep(_ samples: [Float], skippingFirst first: Int = 0) -> Float {
        var result: Float = 0
        guard samples.count > first + 1 else { return 0 }
        for i in (first + 1)..<samples.count {
            result = max(result, abs(samples[i] - samples[i - 1]))
        }
        return result
    }

    func testCoefficientSwingMidStreamHasNoDiscontinuity() {
        let skip = blockSize * 2
        let yardstick = max(
            maxStep(render(startGain: 12, swing: nil), skippingFirst: skip),
            maxStep(render(startGain: -12, swing: nil), skippingFirst: skip)
        )
        let swung = render(startGain: 12, swing: (block: 6, gain: -12))
        let worst = maxStep(swung, skippingFirst: skip)
        print("D5 zipper: yardstick max step \(yardstick), swung max step \(worst)")
        XCTAssertGreaterThan(yardstick, 0)
        XCTAssertLessThanOrEqual(
            worst, yardstick * 2,
            "a mid-stream coefficient swing must not step beyond 2x the settled slope (yardstick \(yardstick), worst \(worst); measured at D5 as exactly 1.0x — the bound leaves regression headroom, not slack)"
        )
    }
}
