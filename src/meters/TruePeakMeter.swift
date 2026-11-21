// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
// TruePeakMeter.swift
// ITU-R BS.1770-4 4x polyphase FIR oversampled True-Peak (dBTP) detector and lookahead True-Peak limiter.

import Atomics
import Foundation

/// ITU-R BS.1770-4 compliant 4x oversampled polyphase FIR True-Peak detector.
///
/// Reconstructs inter-sample peaks (ISPs) at 4x the native sample rate using four 12-tap
/// Kaiser-windowed sinc polyphase branches (48 taps total at `4 * fs`).
///
/// All state buffers are pre-allocated at initialization; `processPeak(buffer:frameCount:)`
/// is 100% real-time safe (zero heap allocations, zero locks).
final class TruePeakDetector {
    // MARK: - Constants

    /// Taps per polyphase branch (48 taps / 4 phases = 12 taps per phase).
    static let tapsPerPhase = 12

    /// Precomputed 4-phase x 12-tap polyphase Kaiser-windowed sinc coefficients
    /// for fractional delays `tau = {0.0, 0.25, 0.50, 0.75}` samples.
    static let polyphaseCoeffs: [[Float]] = {
        let phases = 4
        let taps = tapsPerPhase
        let center = Double(taps / 2 - 1) // 5.0
        var table: [[Float]] = []

        for p in 0..<phases {
            if p == 0 {
                // Phase 0 is exact integer sample delay at center tap
                var row = [Float](repeating: 0.0, count: taps)
                row[Int(center)] = 1.0
                table.append(row)
                continue
            }

            let tau = Double(p) / Double(phases)
            var raw = [Double](repeating: 0.0, count: taps)
            var sum = 0.0
            let halfLen = Double(taps) * 0.5

            for k in 0..<taps {
                let x = Double(k) - center - tau
                let sincVal = abs(x) < 1e-12 ? 1.0 : sin(.pi * x) / (.pi * x)
                // Raised-cosine / Hann-Bessel window over [-halfLen, +halfLen]
                let norm = x / halfLen
                let w = abs(norm) >= 1.0 ? 0.0 : 0.5 * (1.0 + cos(.pi * norm))
                let coeff = sincVal * w
                raw[k] = coeff
                sum += coeff
            }

            // Normalize for exact unity DC gain on each polyphase branch
            let invSum = sum != 0 ? 1.0 / sum : 1.0
            table.append(raw.map { Float($0 * invSum) })
        }
        return table
    }()

    // Flat 36-element tuple/array for phases 1, 2, 3 (12 taps each)
    private let c1_0: Float, c1_1: Float, c1_2: Float, c1_3: Float, c1_4: Float, c1_5: Float
    private let c1_6: Float, c1_7: Float, c1_8: Float, c1_9: Float, c1_10: Float, c1_11: Float

    private let c2_0: Float, c2_1: Float, c2_2: Float, c2_3: Float, c2_4: Float, c2_5: Float
    private let c2_6: Float, c2_7: Float, c2_8: Float, c2_9: Float, c2_10: Float, c2_11: Float

    private let c3_0: Float, c3_1: Float, c3_2: Float, c3_3: Float, c3_4: Float, c3_5: Float
    private let c3_6: Float, c3_7: Float, c3_8: Float, c3_9: Float, c3_10: Float, c3_11: Float

    /// Pre-allocated delay line per detector instance (size 12).
    private let history: UnsafeMutablePointer<Float>

    // MARK: - Initialization

    init() {
        let p1 = Self.polyphaseCoeffs[1]
        c1_0 = p1[0]; c1_1 = p1[1]; c1_2 = p1[2]; c1_3 = p1[3]; c1_4 = p1[4]; c1_5 = p1[5]
        c1_6 = p1[6]; c1_7 = p1[7]; c1_8 = p1[8]; c1_9 = p1[9]; c1_10 = p1[10]; c1_11 = p1[11]

        let p2 = Self.polyphaseCoeffs[2]
        c2_0 = p2[0]; c2_1 = p2[1]; c2_2 = p2[2]; c2_3 = p2[3]; c2_4 = p2[4]; c2_5 = p2[5]
        c2_6 = p2[6]; c2_7 = p2[7]; c2_8 = p2[8]; c2_9 = p2[9]; c2_10 = p2[10]; c2_11 = p2[11]

        let p3 = Self.polyphaseCoeffs[3]
        c3_0 = p3[0]; c3_1 = p3[1]; c3_2 = p3[2]; c3_3 = p3[3]; c3_4 = p3[4]; c3_5 = p3[5]
        c3_6 = p3[6]; c3_7 = p3[7]; c3_8 = p3[8]; c3_9 = p3[9]; c3_10 = p3[10]; c3_11 = p3[11]

        history = UnsafeMutablePointer<Float>.allocate(capacity: Self.tapsPerPhase)
        history.initialize(repeating: 0.0, count: Self.tapsPerPhase)
    }

    deinit {
        history.deinitialize(count: Self.tapsPerPhase)
        history.deallocate()
    }

    /// Resets the internal FIR delay line to silence.
    @inline(__always)
    func reset() {
        for i in 0..<Self.tapsPerPhase {
            history[i] = 0.0
        }
    }

    /// Evaluates the 4x oversampled True-Peak of a single sample `x` and advances state.
    @inline(__always)
    func processSample(_ x: Float) -> Float {
        let h10 = history[9]
        let h9  = history[8]
        let h8  = history[7]
        let h7  = history[6]
        let h6  = history[5]
        let h5  = history[4]
        let h4  = history[3]
        let h3  = history[2]
        let h2  = history[1]
        let h1  = history[0]
        let h11 = history[10]

        history[10] = h10
        history[9]  = h9
        history[8]  = h8
        history[7]  = h7
        history[6]  = h6
        history[5]  = h5
        history[4]  = h4
        history[3]  = h3
        history[2]  = h2
        history[1]  = h1
        history[0]  = x

        let y0 = abs(x)
        let y0_delayed = abs(h5)

        let y1 = abs(
            c1_0 * x + c1_1 * h1 + c1_2 * h2 + c1_3 * h3 + c1_4 * h4 + c1_5 * h5
            + c1_6 * h6 + c1_7 * h7 + c1_8 * h8 + c1_9 * h9 + c1_10 * h10 + c1_11 * h11
        )
        let y2 = abs(
            c2_0 * x + c2_1 * h1 + c2_2 * h2 + c2_3 * h3 + c2_4 * h4 + c2_5 * h5
            + c2_6 * h6 + c2_7 * h7 + c2_8 * h8 + c2_9 * h9 + c2_10 * h10 + c2_11 * h11
        )
        let y3 = abs(
            c3_0 * x + c3_1 * h1 + c3_2 * h2 + c3_3 * h3 + c3_4 * h4 + c3_5 * h5
            + c3_6 * h6 + c3_7 * h7 + c3_8 * h8 + c3_9 * h9 + c3_10 * h10 + c3_11 * h11
        )

        return max(max(y0, y0_delayed), max(y1, max(y2, y3)))
    }

    /// Computes the maximum 4x oversampled True-Peak (linear amplitude) across a buffer.
    @inline(__always)
    func processPeak(buffer: UnsafePointer<Float>, frameCount: Int) -> Float {
        guard frameCount > 0 else { return 0.0 }
        var maxTruePeak: Float = 0.0
        for i in 0..<frameCount {
            let tp = processSample(buffer[i])
            if tp > maxTruePeak {
                maxTruePeak = tp
            }
        }
        return maxTruePeak
    }

    /// Computes True-Peak in dBTP across a buffer.
    @inline(__always)
    func processPeakDBTP(
        buffer: UnsafePointer<Float>,
        frameCount: Int,
        silence: Float = MeterConstants.silenceDB
    ) -> Float {
        let linearTP = processPeak(buffer: buffer, frameCount: frameCount)
        return AudioMath.linearToDB(max(linearTP, 1e-7), silence: silence)
    }
}

/// Real-time safe True-Peak Ceiling Limiter (the render pipeline configures it at
/// `-1.0 dBTP`; the `-0.15 dBTP` init default applies only to standalone use).
///
/// Uses a `TruePeakDetector` (4x polyphase, 5.5-sample group delay) and a 12-sample
/// lookahead delay line. Gain reduction ramps linearly over the 6 samples between
/// detection and the delayed peak's exit, so no single sample carries the whole step.
/// After the peak, gain holds for 25 ms (longer than a full 40 Hz cycle, so
/// sustained bass is ridden at constant gain rather than waveshaped) and then
/// releases with an 80 ms time constant. Hold and release are derived from the sample rate in
/// `configure(sampleRate:)`; the attack stays 6 samples at every rate because the
/// lookahead window is fixed in samples.
final class TruePeakLimiter {
    private let detector = TruePeakDetector()
    private let lookaheadLength = 12
    /// Samples between detector recognition and the delayed peak's exit:
    /// the 12-sample lookahead minus the detector's 5.5-sample group delay.
    private let attackSteps = 6
    private let delayLine: UnsafeMutablePointer<Float>
    private var writePos: Int = 0
    private var currentGain: Float = 1.0
    private var targetGain: Float = 1.0
    private var attackStep: Float = 0.0
    private var attackCounter: Int = 0
    private var holdCounter: Int = 0
    /// Post-peak hold in samples: the attack window plus 25 ms at the configured rate.
    private var holdSamples: Int = 1206
    /// Release pole for an 80 ms time constant at the configured sample rate.
    private var releaseCoeff: Float = 0.99974

    /// Shallowest gain applied since the control side last consumed
    /// the peak gain reduction (linear Float bit pattern; 1.0 = no limiting).
    /// Atomic for race-free audio-thread writes and control-thread consume.
    private let minGainSinceReadAtomic = ManagedAtomic<UInt32>(Float(1.0).bitPattern)

    /// Control side: the peak gain reduction in dB (>= 0) since the
    /// last call; atomically resets the tracker to unity.
    func consumeMaxGainReductionDB() -> Float {
        let bits = minGainSinceReadAtomic.exchange(Float(1.0).bitPattern, ordering: .acquiringAndReleasing)
        let minGain = Float(bitPattern: bits)
        guard minGain < 1.0 else { return 0 }
        return -20.0 * log10f(minGain)
    }

    /// Linear ceiling amplitude.
    let ceilingLinear: Float

    init(ceilingDBTP: Float = -0.15) {
        self.ceilingLinear = pow(10.0, ceilingDBTP / 20.0)
        delayLine = UnsafeMutablePointer<Float>.allocate(capacity: lookaheadLength)
        delayLine.initialize(repeating: 0.0, count: lookaheadLength)
    }

    deinit {
        delayLine.deinitialize(count: lookaheadLength)
        delayLine.deallocate()
    }

    /// Derives hold and release from the sample rate. Call from the control side
    /// when the pipeline is configured; the defaults assume 48 kHz.
    func configure(sampleRate: Double) {
        holdSamples = attackSteps + Int(0.025 * sampleRate + 0.5)
        releaseCoeff = Float(exp(-1.0 / (0.080 * sampleRate)))
    }

    @inline(__always)
    func reset() {
        detector.reset()
        for i in 0..<lookaheadLength {
            delayLine[i] = 0.0
        }
        writePos = 0
        currentGain = 1.0
        targetGain = 1.0
        attackStep = 0.0
        attackCounter = 0
        holdCounter = 0
        minGainSinceReadAtomic.store(Float(1.0).bitPattern, ordering: .relaxed)
    }

    /// Advances the gain state machine by one sample and returns the
    /// gain to apply. This is the single definition of the attack /
    /// hold / release behaviour, shared by independent and linked
    /// processing so the two can never drift apart.
    @inline(__always)
    private func stepGain(requiredGain: Float) -> Float {
        if requiredGain < targetGain {
            // Ramp down across the remaining lookahead. A mid-ramp peak that
            // demands a steeper descent steepens the slope; a shallower one
            // never flattens it, so a peak already in flight stays covered.
            let candidateStep = (requiredGain - currentGain) / Float(attackSteps)
            if attackCounter == 0 || candidateStep < attackStep {
                attackStep = candidateStep
            }
            targetGain = requiredGain
            attackCounter = attackSteps
        }
        if requiredGain < 1.0 {
            // The programme is still at the ceiling, whether or not it
            // demands a deeper cut than the standing one: keep holding.
            // Refreshing only on deeper cuts lets the hold expire under a
            // continuous tone, and the release/re-attack sawtooth that
            // follows measures as bass THD.
            holdCounter = holdSamples
        }

        if attackCounter > 0 {
            currentGain += attackStep
            attackCounter -= 1
            if attackCounter == 0 || currentGain <= targetGain {
                currentGain = targetGain
                attackCounter = 0
                attackStep = 0.0
            }
        } else if holdCounter > 0 {
            holdCounter -= 1
        } else if currentGain < 1.0 {
            currentGain = releaseCoeff * currentGain + (1.0 - releaseCoeff) * 1.0
            targetGain = currentGain
            if currentGain > 0.99999 { currentGain = 1.0; targetGain = 1.0 }
        }
        let prevMin = Float(bitPattern: minGainSinceReadAtomic.load(ordering: .relaxed))
        if currentGain < prevMin {
            minGainSinceReadAtomic.store(currentGain.bitPattern, ordering: .relaxed)
        }
        return currentGain
    }

    /// Processes `frameCount` samples in-place, guaranteeing True-Peak <= the ceiling.
    @inline(__always)
    func processInPlace(buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        let ceiling = ceilingLinear
        let len = lookaheadLength

        for i in 0..<frameCount {
            let raw = buffer[i]
            let inputSample: Float = raw.isFinite ? raw : 0.0
            let tp = detector.processSample(inputSample)

            // Read delayed sample aligned with polyphase FIR centre
            let delayedSample = delayLine[writePos]
            delayLine[writePos] = inputSample
            writePos += 1
            if writePos >= len { writePos = 0 }

            let requiredGain: Float = (tp.isFinite && tp > ceiling) ? (ceiling / tp) : 1.0
            let out = delayedSample * stepGain(requiredGain: requiredGain)
            buffer[i] = out.isFinite ? out : 0.0
        }
    }

    /// Linked stereo processing: one gain trajectory (this limiter's
    /// state), driven per sample by the deeper of the two channels'
    /// required gains and applied to both, so limiting never shifts the
    /// stereo image. The partner contributes its detector and delay
    /// line; its gain state stays unused while linked.
    ///
    /// Used only in Linked channel mode. Stereo mode keeps independent
    /// limiters: asymmetric hearing compensation must never be ducked
    /// by the other ear.
    @inline(__always)
    func processLinkedPairInPlace(
        other: TruePeakLimiter,
        leftBuffer: UnsafeMutablePointer<Float>,
        rightBuffer: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        for i in 0..<frameCount {
            let rawLeft = leftBuffer[i]
            let rawRight = rightBuffer[i]
            let leftInput: Float = rawLeft.isFinite ? rawLeft : 0.0
            let rightInput: Float = rawRight.isFinite ? rawRight : 0.0
            let leftTP = detector.processSample(leftInput)
            let rightTP = other.detector.processSample(rightInput)

            // Read delayed samples aligned with polyphase FIR centre
            let leftDelayed = delayLine[writePos]
            delayLine[writePos] = leftInput
            writePos += 1
            if writePos >= lookaheadLength { writePos = 0 }

            let rightDelayed = other.delayLine[other.writePos]
            other.delayLine[other.writePos] = rightInput
            other.writePos += 1
            if other.writePos >= other.lookaheadLength { other.writePos = 0 }

            let leftRequired: Float = (leftTP.isFinite && leftTP > ceilingLinear) ? (ceilingLinear / leftTP) : 1.0
            let rightRequired: Float = (rightTP.isFinite && rightTP > other.ceilingLinear) ? (other.ceilingLinear / rightTP) : 1.0
            let gain = stepGain(requiredGain: min(leftRequired, rightRequired))

            let leftOut = leftDelayed * gain
            let rightOut = rightDelayed * gain
            leftBuffer[i] = leftOut.isFinite ? leftOut : 0.0
            rightBuffer[i] = rightOut.isFinite ? rightOut : 0.0
        }
    }
}
