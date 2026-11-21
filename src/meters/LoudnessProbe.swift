// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Atomics
import Foundation

/// BS.1770 K-weighting filter design.
///
/// The standard publishes exact coefficients only for 48 kHz. The two
/// stages are therefore carried as their analogue prototypes —
/// recovered from the published 48 kHz coefficients by inverse
/// bilinear transform (round-trip exact to 2e-16) — and re-warped to
/// any sample rate with the bilinear transform. At 48 kHz the
/// published coefficients come back exactly; at 44.1 kHz the response
/// tracks the analogue curve within 0.02 dB, at 96 kHz within
/// 0.005 dB.
enum KWeighting {
    struct BiquadCoefficients: Equatable {
        var b0: Double
        var b1: Double
        var b2: Double
        var a1: Double
        var a2: Double
    }

    // Analogue prototypes: (n2 s^2 + n1 s + n0) / (s^2 + d1 s + d0).
    // Stage 1 is the pre-filter shelf (+4 dB high-frequency shelf:
    // n2 = 10^(4/20), n0 = d0 for unity at DC). Stage 2 is the RLB
    // high-pass (numerator proportional to s^2).
    private static let stage1Numerator = (n2: 1.5848647011308554, n1: 18886.9143780289, n0: 112594507.26979087)
    private static let stage1Denominator = (d1: 15004.846526655718, d0: 112594507.26978998)
    private static let stage2Numerator = (n2: 1.0049948987146884, n1: 0.0, n0: 0.0)
    private static let stage2Denominator = (d1: 478.91221140842475, d0: 57414.25935862601)

    /// Digital coefficients for both K-weighting stages at a sample rate.
    static func coefficients(sampleRate: Double) -> (stage1: BiquadCoefficients, stage2: BiquadCoefficients) {
        (
            stage1: warp(numerator: stage1Numerator, denominator: stage1Denominator, sampleRate: sampleRate),
            stage2: warp(numerator: stage2Numerator, denominator: stage2Denominator, sampleRate: sampleRate)
        )
    }

    /// Bilinear transform of an analogue biquad to the given rate.
    private static func warp(
        numerator: (n2: Double, n1: Double, n0: Double),
        denominator: (d1: Double, d0: Double),
        sampleRate: Double
    ) -> BiquadCoefficients {
        let c = 2.0 * sampleRate
        let b0 = numerator.n2 * c * c + numerator.n1 * c + numerator.n0
        let b1 = -2.0 * numerator.n2 * c * c + 2.0 * numerator.n0
        let b2 = numerator.n2 * c * c - numerator.n1 * c + numerator.n0
        let a0 = c * c + denominator.d1 * c + denominator.d0
        let a1 = -2.0 * c * c + 2.0 * denominator.d0
        let a2 = c * c - denominator.d1 * c + denominator.d0
        return BiquadCoefficients(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }
}

/// Audio-thread loudness probe: K-filters the first two channels and
/// accumulates mean-square energies in 400 ms blocks at a 100 ms hop
/// (BS.1770 block geometry). Completed block energies (z, the summed
/// channel mean squares) are published through a small lock-free ring
/// for the control thread to drain; gating and LUFS maths live in
/// `LoudnessMeter`.
///
/// `@unchecked Sendable`: written only from the audio thread, drained
/// only from the control thread; the ring indices are atomic.
final class LoudnessProbe: @unchecked Sendable {
    private struct FilterState {
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    }

    private var stage1: KWeighting.BiquadCoefficients?
    private var stage2: KWeighting.BiquadCoefficients?
    private var filterStates: [(stage1: FilterState, stage2: FilterState)] = [(FilterState(), FilterState()), (FilterState(), FilterState())]

    private var hopFrames = 4800
    private var hopSumSquares = 0.0
    private var hopFrameCount = 0
    /// Mean-square sums (z) of the last four hops; a block completes
    /// on every hop once four hops exist.
    private var recentHopZ: [Double] = []

    private static let ringCapacity = 256
    private var ring: [Double] = [Double](repeating: 0, count: ringCapacity)
    private let ringWrite = ManagedAtomic<Int>(0)
    private let ringRead = ManagedAtomic<Int>(0)

    /// Designs the K filters for a sample rate and clears all state.
    func configure(sampleRate: Double) {
        let coeffs = KWeighting.coefficients(sampleRate: sampleRate)
        stage1 = coeffs.stage1
        stage2 = coeffs.stage2
        hopFrames = max(1, Int(sampleRate / 10.0))
        resetAccumulation()
    }

    /// Clears filter state, partial blocks, and undrained blocks.
    func reset() {
        filterStates = [(FilterState(), FilterState()), (FilterState(), FilterState())]
        resetAccumulation()
        ringRead.store(ringWrite.load(ordering: .relaxed), ordering: .relaxed)
    }

    private func resetAccumulation() {
        hopSumSquares = 0
        hopFrameCount = 0
        recentHopZ = []
    }

    /// Feeds interleaved-by-channel (non-interleaved) buffers.
    /// Only the first two channels are metered (programme loudness
    /// for this app is stereo; a lone channel is metered singly).
    func feed(buffers: [UnsafePointer<Float>], frameCount: Int) {
        guard let s1 = stage1, let s2 = stage2, frameCount > 0 else { return }
        let channels = min(2, buffers.count)
        guard channels > 0 else { return }

        for frame in 0..<frameCount {
            var frameSum = 0.0
            for ch in 0..<channels {
                let x = Double(buffers[ch][frame])
                var state = filterStates[ch]
                let y1 = s1.b0 * x + s1.b1 * state.stage1.x1 + s1.b2 * state.stage1.x2
                    - s1.a1 * state.stage1.y1 - s1.a2 * state.stage1.y2
                state.stage1.x2 = state.stage1.x1
                state.stage1.x1 = x
                state.stage1.y2 = state.stage1.y1
                state.stage1.y1 = y1
                let y2 = s2.b0 * y1 + s2.b1 * state.stage2.x1 + s2.b2 * state.stage2.x2
                    - s2.a1 * state.stage2.y1 - s2.a2 * state.stage2.y2
                state.stage2.x2 = state.stage2.x1
                state.stage2.x1 = y1
                state.stage2.y2 = state.stage2.y1
                state.stage2.y1 = y2
                filterStates[ch] = state
                frameSum += y2 * y2
            }
            hopSumSquares += frameSum
            hopFrameCount += 1
            if hopFrameCount >= hopFrames {
                completeHop()
            }
        }
    }

    private func completeHop() {
        let hopZ = hopSumSquares / Double(hopFrames)
        hopSumSquares = 0
        hopFrameCount = 0
        recentHopZ.append(hopZ)
        if recentHopZ.count > 4 { recentHopZ.removeFirst() }
        guard recentHopZ.count == 4 else { return }
        let blockZ = recentHopZ.reduce(0, +) / 4.0
        let write = ringWrite.load(ordering: .relaxed)
        ring[write % Self.ringCapacity] = blockZ
        ringWrite.store(write + 1, ordering: .relaxed)
    }

    /// Drains completed block energies. Control thread only.
    func drainBlocks() -> [Double] {
        let write = ringWrite.load(ordering: .relaxed)
        var read = ringRead.load(ordering: .relaxed)
        // If the writer lapped the ring, the oldest blocks are lost;
        // skip to the oldest surviving block.
        if write - read > Self.ringCapacity {
            read = write - Self.ringCapacity
        }
        var blocks: [Double] = []
        while read < write {
            blocks.append(ring[read % Self.ringCapacity])
            read += 1
        }
        ringRead.store(read, ordering: .relaxed)
        return blocks
    }
}
