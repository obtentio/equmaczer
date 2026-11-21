// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import Accelerate
import Atomics
import Foundation

/// Chain of 64 second-order `Float64` TPT SVF filters for one audio channel.
///
/// Pre-allocates `maxBandCount` filters and raw unmanaged staging buffers at `init`.
/// Uses a bounded SPSC triple-buffer exchange (`ManagedAtomic<Int>`) so main-thread
/// updates (`stageBandUpdate`, `stageFullUpdate`) and audio-thread consumption
/// (`applyPendingUpdates`) are 100% lock-free, allocation-free, `free()`-free, and race-free.
final class EQChain {
    // MARK: - Constants

    /// Maximum number of bands per layer (from EQConfiguration).
    static let maxBandCount = EQConfiguration.maxBandCount

    // MARK: - Properties

    /// Pre-allocated `Float64` TPT SVF filters (one per band).
    private let filtersPtr: UnsafeMutablePointer<BiquadFilter>

    /// Number of active bands in this chain (audio thread only).
    private var activeBandCount: Int = 0

    /// Per-band bypass flags owned by the audio thread.
    private let bypassFlagsPtr: UnsafeMutablePointer<Bool>

    /// Layer-level bypass (audio thread only).
    private var layerBypass: Bool = false

    /// Pre-allocated contiguous `Float64` work buffer so multi-band cascades run
    /// in full 64-bit precision without intermediate `Float32` truncation.
    private let doubleBufferPtr: UnsafeMutablePointer<Double>
    private let doubleBufferCapacity: Int

    // MARK: - Producer state and owned publication buffers

    /// Coefficients currently in use by the audio thread.
    private let activeCoefficientsPtr: UnsafeMutablePointer<SVFCoefficients>

    /// Coefficients staged for next update (written by main thread).
    private let pendingCoefficientsPtr: UnsafeMutablePointer<SVFCoefficients>

    /// Staged per-band bypass flags (written by main thread).
    private let pendingBypassFlagsPtr: UnsafeMutablePointer<Bool>

    // SPSC triple buffer: producer owns back, consumer owns front, and only
    // the middle index is exchanged. A buffer cannot be written while read.
    private struct PublishedState {
        let coefficients: UnsafeMutablePointer<SVFCoefficients>
        let bypass: UnsafeMutablePointer<Bool>
        var count = 0
        var layerBypass = false
        var resetGeneration: UInt64 = 0
    }
    private let published: UnsafeMutablePointer<PublishedState>
    private let middle = ManagedAtomic<Int>(1)
    private var producerBack = 2             // producer only
    private var consumerFront = 0            // audio thread only
    private var stagedCount = 0              // producer only
    private var stagedLayerBypass = false
    private var stagedResetGeneration: UInt64 = 0
    private var appliedResetGeneration: UInt64 = 0 // audio thread only

    // MARK: - Initialization

    /// Creates a new EQ chain with pre-allocated raw buffers and TPT SVF filters.
    init(maxFrameCount: UInt32) {
        let count = Self.maxBandCount
        filtersPtr = UnsafeMutablePointer<BiquadFilter>.allocate(capacity: count)
        for i in 0..<count {
            filtersPtr.advanced(by: i).initialize(to: BiquadFilter())
        }

        activeCoefficientsPtr = UnsafeMutablePointer<SVFCoefficients>.allocate(capacity: count)
        activeCoefficientsPtr.initialize(repeating: .identity, count: count)

        pendingCoefficientsPtr = UnsafeMutablePointer<SVFCoefficients>.allocate(capacity: count)
        pendingCoefficientsPtr.initialize(repeating: .identity, count: count)

        bypassFlagsPtr = UnsafeMutablePointer<Bool>.allocate(capacity: count)
        bypassFlagsPtr.initialize(repeating: false, count: count)

        pendingBypassFlagsPtr = UnsafeMutablePointer<Bool>.allocate(capacity: count)
        pendingBypassFlagsPtr.initialize(repeating: false, count: count)

        published = .allocate(capacity: 3)
        for i in 0..<3 {
            let coefficients = UnsafeMutablePointer<SVFCoefficients>.allocate(capacity: count)
            coefficients.initialize(repeating: .identity, count: count)
            let bypass = UnsafeMutablePointer<Bool>.allocate(capacity: count)
            bypass.initialize(repeating: false, count: count)
            published.advanced(by: i).initialize(to: PublishedState(coefficients: coefficients, bypass: bypass))
        }
        doubleBufferCapacity = max(Int(maxFrameCount), 65536)
        doubleBufferPtr = UnsafeMutablePointer<Double>.allocate(capacity: doubleBufferCapacity)
        doubleBufferPtr.initialize(repeating: 0.0, count: doubleBufferCapacity)
    }

    deinit {
        let count = Self.maxBandCount
        filtersPtr.deinitialize(count: count)
        filtersPtr.deallocate()

        activeCoefficientsPtr.deinitialize(count: count)
        activeCoefficientsPtr.deallocate()

        pendingCoefficientsPtr.deinitialize(count: count)
        pendingCoefficientsPtr.deallocate()

        bypassFlagsPtr.deinitialize(count: count)
        bypassFlagsPtr.deallocate()

        pendingBypassFlagsPtr.deinitialize(count: count)
        pendingBypassFlagsPtr.deallocate()

        for i in 0..<3 {
            published[i].coefficients.deinitialize(count: count)
            published[i].coefficients.deallocate()
            published[i].bypass.deinitialize(count: count)
            published[i].bypass.deallocate()
        }
        published.deinitialize(count: 3)
        published.deallocate()
        doubleBufferPtr.deinitialize(count: doubleBufferCapacity)
        doubleBufferPtr.deallocate()
    }

    // MARK: - Main Thread API

    /// Stages new coefficients for a single band (called from main thread).
    ///
    /// Incremental update path — used for live slider drags.
    /// Does NOT set `pendingFullReset`, so `applyPendingUpdates()` preserves TPT SVF
    /// integrator state and smoothly interpolates parameters per-sample.
    func stageBandUpdate(index: Int, coefficients: SVFCoefficients, bypass: Bool) {
        guard index >= 0 && index < Self.maxBandCount else { return }
        pendingCoefficientsPtr[index] = coefficients
        pendingBypassFlagsPtr[index] = bypass
        publish()
    }

    func stageFullUpdate(coefficients: [SVFCoefficients], bypassFlags: [Bool], activeBandCount: Int, layerBypass: Bool) {
        for i in 0..<Self.maxBandCount {
            pendingCoefficientsPtr[i] = i < coefficients.count ? coefficients[i] : .identity
            pendingBypassFlagsPtr[i] = i < bypassFlags.count ? bypassFlags[i] : false
        }
        stagedCount = max(0, min(activeBandCount, Self.maxBandCount))
        stagedLayerBypass = layerBypass
        stagedResetGeneration &+= 1
        publish()
    }

    func stageLayerBypass(_ bypass: Bool) {
        stagedLayerBypass = bypass
        publish()
    }

    /// Only the producer writes its private canonical arrays and back buffer.
    private func publish() {
        let back = published.advanced(by: producerBack)
        back.pointee.coefficients.update(from: pendingCoefficientsPtr, count: Self.maxBandCount)
        back.pointee.bypass.update(from: pendingBypassFlagsPtr, count: Self.maxBandCount)
        back.pointee.count = stagedCount
        back.pointee.layerBypass = stagedLayerBypass
        back.pointee.resetGeneration = stagedResetGeneration
        // Bit 2 means a new complete snapshot is available; lower bits identify it.
        producerBack = middle.exchange(producerBack | 4, ordering: .acquiringAndReleasing) & 3
    }

    /// Bounded: one exchange and one fixed-size copy, no retry, locks or allocation.
    @inline(__always)
    func applyPendingUpdates() {
        guard middle.load(ordering: .acquiring) & 4 != 0 else { return }
        consumerFront = middle.exchange(consumerFront, ordering: .acquiringAndReleasing) & 3
        let front = published.advanced(by: consumerFront)
        let fullReset = front.pointee.resetGeneration != appliedResetGeneration
        for i in 0..<Self.maxBandCount {
            bypassFlagsPtr[i] = front.pointee.bypass[i]
            let coefficient = front.pointee.coefficients[i]
            if fullReset || coefficient != activeCoefficientsPtr[i] {
                activeCoefficientsPtr[i] = coefficient
                filtersPtr[i].setSVFCoefficients(coefficient, resetState: fullReset)
            }
        }
        activeBandCount = front.pointee.count
        layerBypass = front.pointee.layerBypass
        appliedResetGeneration = front.pointee.resetGeneration
    }

    /// Processes audio through all active bands in this chain in-place.
    /// Converts `Float32 -> Float64` once on entry, runs the full cascade in `Float64`
    /// without inter-band `Float32` quantization, and converts `Float64 -> Float32` on exit.
    @inline(__always)
    func process(buffer: UnsafeMutablePointer<Float>, frameCount: UInt32) {
        if layerBypass || activeBandCount == 0 || frameCount == 0 {
            return
        }

        let count = activeBandCount
        var hasUnbypassedBand = false
        var b = 0
        while b < count {
            if !bypassFlagsPtr[b] {
                hasUnbypassedBand = true
                break
            }
            b &+= 1
        }
        if !hasUnbypassedBand {
            return
        }

        var remaining = Int(frameCount)
        var offset = 0
        while remaining > 0 {
            let chunk = min(remaining, doubleBufferCapacity)
            let chunkPtr = buffer.advanced(by: offset)
            vDSP_vspdp(chunkPtr, 1, doubleBufferPtr, 1, vDSP_Length(chunk))

            var i = 0
            while i < count {
                if !bypassFlagsPtr[i] {
                    filtersPtr[i].processDoubleInPlace(buffer: doubleBufferPtr, frameCount: chunk)
                }
                i &+= 1
            }

            vDSP_vdpsp(doubleBufferPtr, 1, chunkPtr, 1, vDSP_Length(chunk))
            offset &+= chunk
            remaining &-= chunk
        }
    }
}
