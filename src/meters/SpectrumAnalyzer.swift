// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Accelerate
import Atomics
import Foundation

/// Real-time output spectrum: the audio thread feeds the final output
/// samples into a single-producer ring; the control side runs a
/// Hann-windowed vDSP FFT and folds it into log-spaced bands with
/// per-band smoothing (fast attack, slow release).
///
/// A live spectrum of the signal being shaped is the one visual an EQ
/// was missing here — the stage shows the composite curve's effect on
/// real programme, not on silence. Implemented natively on the meter
/// pipeline; no third-party code.
final class SpectrumAnalyzer {
    static let bandCount = 48
    static let fftSize = 2048
    static let floorDB: Float = -90
    private static let log2Size = vDSP_Length(11)  // log2(fftSize)

    private static let ringCapacity = 8192

    private let ring: UnsafeMutablePointer<Float>
    private let writeCounter = ManagedAtomic<Int>(0)
    private var sampleRate: Double = 48000

    private var smoothed: [Float]
    private let window: [Float]
    /// Sum of the window values — the FFT's coherent gain. Levels are
    /// normalised by it (and by the zrip transform's factor of two),
    /// so a bin-centred full-scale sine reads 0 dB.
    private let windowSum: Float
    private var fftSetup: FFTSetup?

    init() {
        ring = .allocate(capacity: Self.ringCapacity)
        ring.initialize(repeating: 0, count: Self.ringCapacity)
        smoothed = [Float](repeating: Self.floorDB, count: Self.bandCount)
        var hann = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&hann, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        window = hann
        windowSum = hann.reduce(0, +)
        fftSetup = vDSP_create_fftsetup(Self.log2Size, FFTRadix(kFFTRadix2))
    }

    deinit {
        ring.deinitialize(count: Self.ringCapacity)
        ring.deallocate()
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    func configure(sampleRate: Double) {
        if sampleRate > 0 {
            self.sampleRate = sampleRate
        }
    }

    /// Audio thread: appends the mono mix of the first two channels.
    func feed(buffers: [UnsafePointer<Float>], frameCount: Int) {
        guard !buffers.isEmpty, frameCount > 0 else { return }
        var counter = writeCounter.load(ordering: .relaxed)
        let hasSecond = buffers.count > 1
        for i in 0..<frameCount {
            var sample = buffers[0][i]
            if hasSecond {
                sample = (sample + buffers[1][i]) * 0.5
            }
            ring[counter & (Self.ringCapacity - 1)] = sample
            counter += 1
        }
        writeCounter.store(counter, ordering: .releasing)
    }

    /// Control side: the latest band levels in dBFS, smoothed. Band
    /// centres are log-spaced from 20 Hz to 20 kHz; each band reports
    /// the strongest FFT bin inside it.
    func computeBands() -> [Float] {
        let size = Self.fftSize
        let total = writeCounter.load(ordering: .acquiring)
        guard total > 0, let fftSetup else { return smoothed }

        // Latest `size` samples, oldest first.
        var samples = [Float](repeating: 0, count: size)
        let start = total - min(total, size)
        for i in 0..<size {
            let index = start + i
            samples[i] = index >= 0 ? ring[index & (Self.ringCapacity - 1)] : 0
        }
        samples = vDSP.multiply(samples, window)

        // Real FFT via split-complex packing.
        let half = size / 2
        var realPart = [Float](repeating: 0, count: half)
        var imagPart = [Float](repeating: 0, count: half)
        samples.withUnsafeBufferPointer { ptr in
            realPart.withUnsafeMutableBufferPointer { realPtr in
                imagPart.withUnsafeMutableBufferPointer { imagPtr in
                    var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(half))
                    }
                    vDSP_fft_zrip(fftSetup, &split, 1, Self.log2Size, FFTDirection(FFT_FORWARD))
                }
            }
        }

        // Magnitudes, scaled so a full-scale sine reads ~0 dB.
        var magnitudes = [Float](repeating: 0, count: half)
        realPart.withUnsafeBufferPointer { realPtr in
            imagPart.withUnsafeBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: UnsafeMutablePointer(mutating: realPtr.baseAddress!),
                                            imagp: UnsafeMutablePointer(mutating: imagPtr.baseAddress!))
                magnitudes.withUnsafeMutableBufferPointer { magPtr in
                    vDSP_zvmags(&split, 1, magPtr.baseAddress!, 1, vDSP_Length(half))
                }
            }
        }
        let scale = 1.0 / windowSum
        let binWidth = sampleRate / Double(size)

        for band in 0..<Self.bandCount {
            let low = 20.0 * pow(1000.0, Double(band) / Double(Self.bandCount))
            let high = 20.0 * pow(1000.0, Double(band + 1) / Double(Self.bandCount))
            let firstBin = max(1, Int(low / binWidth))
            let lastBin = min(half - 1, max(firstBin, Int(high / binWidth) - 1))

            var peakSquared: Float = 0
            for bin in firstBin...lastBin {
                if magnitudes[bin] > peakSquared { peakSquared = magnitudes[bin] }
            }
            let peak = sqrt(peakSquared) * scale
            let db = peak > 1e-6 ? 20 * log10(peak) : Self.floorDB
            let target = max(Self.floorDB, db)

            let current = smoothed[band]
            let factor: Float = target > current ? 0.55 : 0.12
            smoothed[band] = current + (target - current) * factor
        }
        return smoothed
    }
}
