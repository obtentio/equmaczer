// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import Accelerate

/// Second-order filter section powered by the `Float64` Topology-Preserving Transform
/// State-Variable Filter (`TPTFilter`).
///
/// Replaces the legacy `Float32` `vDSP_biquad` Direct Form implementation to eliminate:
/// 1. Low-frequency (`20 Hz`, high-`Q`) single-precision mantissa quantization noise.
/// 2. Real-time audio thread `free()` (`vDSP_biquad_DestroySetup`) heap lock contention.
/// 3. Zipper noise and pole-jump transients during live parameter modulation.
final class BiquadFilter {
    // MARK: - Properties

    /// Underlying `Float64` TPT State-Variable Filter engine.
    private let tptFilter = TPTFilter()

    /// Whether a valid coefficient configuration has been installed.
    private var isValid: Bool = false

    /// Non-allocating static setup token used to preserve API compatibility with
    /// callers/tests that pass a `vDSP_biquad_Setup?` token without incurring heap
    /// `malloc`/`free` traffic during coefficient updates or on the audio thread.
    private nonisolated(unsafe) static let sharedSetupToken: vDSP_biquad_Setup? = {
        var identityCoeffs: [Double] = [1.0, 0.0, 0.0, 0.0, 0.0]
        return vDSP_biquad_CreateSetup(&identityCoeffs, 1)
    }()

    // MARK: - Initialization

    init() {
        isValid = false
    }

    // MARK: - Setup Creation (Main Thread API Compatibility)

    /// Returns a non-allocating setup token for API compatibility.
    /// No per-update heap allocation or audio-thread deallocation is performed.
    static func prepareSetup(_ coefficients: BiquadCoefficients) -> vDSP_biquad_Setup? {
        sharedSetupToken
    }

    // MARK: - Coefficient Update (Audio Thread Safe — Zero Allocation / Zero Free)

    /// Updates the filter with new biquad coefficients via the exact TPT SVF isomorphism.
    /// Performs zero heap allocations and zero `free()` calls on the audio thread.
    @inline(__always)
    func setCoefficients(_ newCoefficients: BiquadCoefficients, setup: vDSP_biquad_Setup?, resetState: Bool) {
        guard setup != nil else {
            isValid = false
            if resetState {
                tptFilter.reset()
            }
            return
        }
        isValid = true
        tptFilter.setBiquadCoefficients(newCoefficients, resetState: resetState)
    }

    /// Directly updates the filter with TPT SVF coefficients on the audio thread.
    @inline(__always)
    func setSVFCoefficients(_ newCoefficients: SVFCoefficients, resetState: Bool) {
        isValid = true
        tptFilter.setSVFCoefficients(newCoefficients, resetState: resetState)
    }

    // MARK: - Audio Processing

    /// Processes audio through the `Float64` TPT SVF section.
    /// Input and output may alias (in-place processing supported).
    @inline(__always)
    func process(
        input: UnsafePointer<Float>,
        output: UnsafeMutablePointer<Float>,
        frameCount: UInt32
    ) {
        guard isValid else {
            if input != output {
                memcpy(output, input, Int(frameCount) * MemoryLayout<Float>.size)
            }
            return
        }

        tptFilter.process(
            input: input,
            output: output,
            frameCount: frameCount
        )
    }

    /// Processes audio in-place in full `Float64` precision across a multi-band cascade.
    @inline(__always)
    func processDoubleInPlace(
        buffer: UnsafeMutablePointer<Double>,
        frameCount: Int
    ) {
        guard isValid else { return }
        tptFilter.processDoubleInPlace(buffer: buffer, frameCount: frameCount)
    }
}
