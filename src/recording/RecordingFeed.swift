import Atomics
import CoreAudio

struct RecordingConfiguration: Equatable, Sendable {
    var enabled = false
    var includeMic = false
    var microphoneUID: String?

    static func isAvailable(captureMode: CaptureMode) -> Bool { captureMode == .processTap }
}

/// Installed before the aggregate starts; storage lives until its IOProc stops.
/// Only this feed sees microphone samples. The DAC uses the untouched final mix.
final class RecordingFeed {
    let enabled = ManagedAtomic<Bool>(false)
    let includeMic = ManagedAtomic<Bool>(false)
    /// Reciprocal of the driver's read-side gain, published by the control thread.
    let compensationGainBits = ManagedAtomic<UInt32>(Float(1).bitPattern)
    let micGainBits = ManagedAtomic<UInt32>(Float(1).bitPattern)
    let left: UnsafeMutablePointer<Float>
    let right: UnsafeMutablePointer<Float>
    let capacity: Int
    var driverOutputOffset: Int?
    var micInputOffset = 0
    var micChannelCount = 0

    init(capacity: Int) {
        self.capacity = capacity
        left = .allocate(capacity: capacity)
        right = .allocate(capacity: capacity)
        left.initialize(repeating: 0, count: capacity)
        right.initialize(repeating: 0, count: capacity)
    }

    deinit { left.deallocate(); right.deallocate() }

    func mix(finalLeft: UnsafePointer<Float>, finalRight: UnsafePointer<Float>,
             input: UnsafePointer<AudioBufferList>, frames: Int) {
        let count = min(frames, capacity)
        let on = enabled.load(ordering: .acquiring)
        let mic = on && includeMic.load(ordering: .acquiring) && micChannelCount > 0
        let gain = Float(bitPattern: micGainBits.load(ordering: .relaxed))
        let compensation = Float(bitPattern: compensationGainBits.load(ordering: .relaxed))
        for frame in 0..<count {
            left[frame] = on ? finalLeft[frame] : 0
            right[frame] = on ? finalRight[frame] : 0
            if mic {
                left[frame] += Self.sample(input, channel: micInputOffset, frame: frame) * gain
                right[frame] += Self.sample(input, channel: micInputOffset + min(1, micChannelCount - 1), frame: frame) * gain
            }
            left[frame] *= compensation
            right[frame] *= compensation
        }
    }

    static func availableFrames(_ list: UnsafePointer<AudioBufferList>, channel: Int) -> Int {
        var base = 0
        for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list)) {
            let channels = Int(buffer.mNumberChannels)
            if channel >= base, channel < base + channels {
                return buffer.mData == nil ? 0 : Int(buffer.mDataByteSize) / (4 * max(1, channels))
            }
            base += channels
        }
        return 0
    }

    /// Flatten planar and interleaved streams without making temporary arrays.
    static func sample(_ list: UnsafePointer<AudioBufferList>, channel: Int, frame: Int) -> Float {
        var base = 0
        for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list)) {
            let channels = Int(buffer.mNumberChannels)
            if channel >= base, channel < base + channels,
               frame < Int(buffer.mDataByteSize) / (4 * max(1, channels)),
               let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                return data[frame * channels + channel - base]
            }
            base += channels
        }
        return 0
    }
}
