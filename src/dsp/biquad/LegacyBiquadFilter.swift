// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
// LegacyBiquadFilter.swift
// Original Float32-state vDSP_biquad implementation retained for comparative benchmarking.

import Accelerate

/// Original `vDSP_biquad` (`Float32` state delay line) filter section from `cvknage/equaliser`.
/// Retained as the baseline reference in `eq-bench` and comparative DSP verification tests.
final class LegacyBiquadFilter {
    private var setup: vDSP_biquad_Setup?
    private var delay: [Float]
    private var isValid: Bool = false

    init() {
        delay = [Float](repeating: 0, count: 4)
        isValid = false
    }

    deinit {
        if let s = setup {
            vDSP_biquad_DestroySetup(s)
        }
    }

    static func prepareSetup(_ coefficients: BiquadCoefficients) -> vDSP_biquad_Setup? {
        var coeffsD: [Double] = [
            coefficients.b0,
            coefficients.b1,
            coefficients.b2,
            coefficients.a1,
            coefficients.a2
        ]
        return vDSP_biquad_CreateSetup(&coeffsD, 1)
    }

    func setCoefficients(_ newCoefficients: BiquadCoefficients, setup: vDSP_biquad_Setup?, resetState: Bool) {
        if let s = self.setup {
            vDSP_biquad_DestroySetup(s)
        }
        self.setup = setup
        if resetState {
            for i in 0..<4 { delay[i] = 0 }
        }
        isValid = setup != nil
    }

    @inline(__always)
    func process(
        input: UnsafePointer<Float>,
        output: UnsafeMutablePointer<Float>,
        frameCount: UInt32
    ) {
        guard isValid, let s = setup else {
            if input != output {
                memcpy(output, input, Int(frameCount) * MemoryLayout<Float>.size)
            }
            return
        }
        delay.withUnsafeMutableBufferPointer { delayPtr in
            vDSP_biquad(s, delayPtr.baseAddress!, input, 1, output, 1, vDSP_Length(frameCount))
        }
    }
}
