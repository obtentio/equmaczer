// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Accelerate
import Atomics
import CoreAudio

/// One stereo tap's storage. The aggregate IOProc is the sole ring producer
/// and consumer; control only publishes EQ snapshots and atomic health flags.
final class ChannelMixerSlot: @unchecked Sendable {
    let channel: AudioChannel
    let bundleID: String?
    let skipEQ: Bool
    let treatsChannel: Bool
    let volumeBits = ManagedAtomic<UInt32>(Float(1).bitPattern)
    private var currentVolume: Float = 1
    private var currentDuck: Float = 1
    let ringBuffer: AudioRingBuffer
    let leftEQ: EQChain
    let rightEQ: EQChain
    let failed = ManagedAtomic<Bool>(false)
    let gainBits = ManagedAtomic<UInt32>(Float(1).bitPattern)
    let left: UnsafeMutablePointer<Float>
    let right: UnsafeMutablePointer<Float>
    private let transport: UnsafeMutablePointer<Float>
    private let frames: Int

    init(channel: AudioChannel, maxFrameCount: UInt32, bundleID: String? = nil, skipEQ: Bool = false, treatsChannel: Bool = true) {
        self.bundleID = bundleID
        self.skipEQ = skipEQ
        self.treatsChannel = treatsChannel
        self.channel = channel
        frames = Int(maxFrameCount)
        ringBuffer = AudioRingBuffer(capacity: max(Int(maxFrameCount) * 4, 2048))
        leftEQ = EQChain(maxFrameCount: maxFrameCount)
        rightEQ = EQChain(maxFrameCount: maxFrameCount)
        left = .allocate(capacity: frames)
        right = .allocate(capacity: frames)
        transport = .allocate(capacity: frames * 2)
        left.initialize(repeating: 0, count: frames)
        right.initialize(repeating: 0, count: frames)
        transport.initialize(repeating: 0, count: frames * 2)
    }

    deinit {
        left.deallocate()
        right.deallocate()
        transport.deallocate()
    }

    /// Copies planar or strided stereo input into a frame-aligned ring.
    /// Producer only. Missing input is silence, never stale scratch samples.
    func write(left: UnsafePointer<Float>, right: UnsafePointer<Float>, stride: Int = 1, rightStride: Int? = nil, frameCount: Int) {
        let count = min(frameCount, frames)
        for frame in 0..<count {
            transport[frame * 2] = left[frame * stride]
            transport[frame * 2 + 1] = right[frame * (rightStride ?? stride)]
        }
        _ = ringBuffer.write(transport, count: count * 2)
    }

    /// Consumer only. Core Audio's sub-tap drift compensation resamples to
    /// the DAC clock. This bounded backlog trim is a recovery guard for
    /// discontinuities; underflow is zero-filled rather than repeated audio.
    func read(frameCount: Int, treated: Bool, duck: Float = 1) {
        let excess = ringBuffer.availableToRead() / 2 - frameCount - ChannelMixer.maximumQueuedFrames
        if excess > 0 { ringBuffer.skipRead(count: excess * 2) }
        _ = ringBuffer.read(into: transport, count: frameCount * 2)
        for frame in 0..<frameCount {
            left[frame] = transport[frame * 2]
            right[frame] = transport[frame * 2 + 1]
        }
        leftEQ.applyPendingUpdates()
        rightEQ.applyPendingUpdates()
        // Slew at most 1/256 per sample, including compare/bypass: volume
        // is independent of EQ. Only this consumer owns currentVolume.
        let target = Float(bitPattern: volumeBits.load(ordering: .relaxed))
        // The duck is a second, independent ramp that multiplies the volume.
        let step = 1 / Float(ChannelMixer.volumeRampFrames)
        let duckStep = ChannelMixer.duckRampStep
        for frame in 0..<frameCount {
            currentVolume += min(max(target - currentVolume, -step), step)
            currentDuck += min(max(duck - currentDuck, -duckStep), duckStep)
            let gain = currentVolume * currentDuck
            left[frame] *= gain
            right[frame] *= gain
        }
        if treated && !skipEQ && treatsChannel {
            var gain = Float(bitPattern: gainBits.load(ordering: .relaxed))
            vDSP_vsmul(left, 1, &gain, left, 1, vDSP_Length(frameCount))
            vDSP_vsmul(right, 1, &gain, right, 1, vDSP_Length(frameCount))
            leftEQ.process(buffer: left, frameCount: UInt32(frameCount))
            rightEQ.process(buffer: right, frameCount: UInt32(frameCount))
        }
    }
}

/// Immutable, pipeline-sized slot table with an atomic active mask. No
/// generation here: tap membership belongs to the coordinator's RouteSeam.
final class ChannelMixer: @unchecked Sendable {
    static let maximumAppSlots = 16
    static let volumeRampFrames = 256
    /// Ducked level for every non-call slot.
    static let duckedGain: Float = 0.15
    /// About 300 ms at 48 kHz for the full 100% to 15% swing (about 327 ms at 44.1 kHz).
    static let duckRampFrames = 14_400
    static let duckRampStep = (1 - duckedGain) / Float(duckRampFrames)
    static let maximumQueuedFrames = 256
    /// Software bound at >=44.1 kHz, including the maximum 16384-frame
    /// callback, recovery backlog and 12-frame master limiter lookahead. Hardware/OS latency is additional.
    static let statedLatencyBudgetMS = 400.0
    let slots: [ChannelMixerSlot]
    let maxFrameCount: UInt32
    /// Target duck gain bits (1 = none). Not a tap change: never touches RouteSeam.
    private let duckBits = ManagedAtomic<UInt32>(Float(1).bitPattern)
    private let activeMask = ManagedAtomic<UInt32>(0)
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>

    init(maxFrameCount: UInt32 = AudioConstants.maxFrameCount, appAssignments: [ChannelTapAssignment] = []) {
        precondition(maxFrameCount > 0)
        self.maxFrameCount = maxFrameCount
        let apps = Array(appAssignments.filter { $0.bundleID != nil }.prefix(Self.maximumAppSlots))
        slots = AudioChannel.allCases.map { ChannelMixerSlot(channel: $0, maxFrameCount: maxFrameCount) }
            + (0..<Self.maximumAppSlots).map { index in
                let app = index < apps.count ? apps[index] : nil
                return ChannelMixerSlot(channel: app?.channel ?? .music, maxFrameCount: maxFrameCount,
                    bundleID: app?.bundleID, skipEQ: app?.skipEQ ?? false, treatsChannel: app?.treatsChannel ?? true)
            }
        left = .allocate(capacity: Int(maxFrameCount))
        right = .allocate(capacity: Int(maxFrameCount))
        left.initialize(repeating: 0, count: Int(maxFrameCount))
        right.initialize(repeating: 0, count: Int(maxFrameCount))
    }

    deinit { left.deallocate(); right.deallocate() }

    /// Control side only. Slot ownership/storage never changes while running.
    func setActive(_ channels: Set<AudioChannel>) {
        var mask: UInt32 = 0
        for index in slots.indices where index < AudioChannel.allCases.count && channels.contains(slots[index].channel) { mask |= 1 << index }
        activeMask.store(mask, ordering: .releasing)
    }

    /// Control side only. Lowers every non-Calls slot to `duckedGain`, ramped.
    func setDucked(_ ducked: Bool) {
        duckBits.store((ducked ? Self.duckedGain : 1).bitPattern, ordering: .relaxed)
    }

    var isDucked: Bool { Float(bitPattern: duckBits.load(ordering: .relaxed)) < 1 }

    func activate(assignments: [ChannelTapAssignment]) {
        var mask: UInt32 = 0
        for assignment in assignments {
            if let index = slots.firstIndex(where: {
                assignment.bundleID == nil ? ($0.bundleID == nil && $0.channel == assignment.channel) : $0.bundleID == assignment.bundleID
            }) { mask |= 1 << index }
        }
        activeMask.store(mask, ordering: .releasing)
    }

    func appSlot(for bundleID: String) -> ChannelMixerSlot? {
        slots.first { $0.bundleID == bundleID }
    }

    func slot(for channel: AudioChannel) -> ChannelMixerSlot {
        // Fixed four-element scan, also safe at callback boundaries.
        slots.first { $0.channel == channel }!
    }

    var failedChannels: Set<AudioChannel> {
        Set(slots.filter { $0.failed.load(ordering: .relaxed) }.map(\.channel))
    }

    /// Borrowed output storage: valid until the next process call, never freed
    /// by the caller. This is also the silence path's output storage.
    func output(_ channel: Int) -> UnsafeMutablePointer<Float> { channel == 0 ? left : right }

    /// Skip-EQ app audio joins after the common EQ/compare gain, before
    /// the shared safety limiter. Uses the already-read slot scratch.
    func addSkipped(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frameCount: Int) {
        let mask = activeMask.load(ordering: .acquiring)
        for index in slots.indices where mask & (1 << index) != 0 {
            let slot = slots[index]
            if slot.skipEQ && !slot.failed.load(ordering: .relaxed) {
                vDSP_vadd(left, 1, slot.left, 1, left, 1, vDSP_Length(frameCount))
                vDSP_vadd(right, 1, slot.right, 1, right, 1, vDSP_Length(frameCount))
            }
        }
    }

    func process(frameCount: UInt32, treated: Bool = true) {
        let count = min(Int(frameCount), Int(maxFrameCount))
        guard count > 0 else { return }
        left.update(repeating: 0, count: count)
        right.update(repeating: 0, count: count)
        let mask = activeMask.load(ordering: .acquiring)
        let duck = Float(bitPattern: duckBits.load(ordering: .relaxed))
        for index in slots.indices where mask & (1 << index) != 0 {
            let slot = slots[index]
            if slot.failed.load(ordering: .relaxed) { continue }
            slot.read(frameCount: count, treated: treated, duck: slot.channel == .calls ? 1 : duck)
            if slot.skipEQ { continue }
            vDSP_vadd(left, 1, slot.left, 1, left, 1, vDSP_Length(count))
            vDSP_vadd(right, 1, slot.right, 1, right, 1, vDSP_Length(count))
        }
    }
}

struct ChannelTapAssignment: Equatable, Sendable {
    let channel: AudioChannel
    let objectIDs: [AudioObjectID]
    var bundleID: String? = nil
    var skipEQ = false
    var treatsChannel = true
}
