// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
// SharedMemoryCapture.swift
// Lock-free audio capture from driver via file-based shared memory

import AudioTransportAtomics
import CoreAudio
import Darwin
import Foundation
import OSLog

// MARK: - Shared Memory Layout

/// Structure matching the shared-memory layout in equmaczerDriver.c
/// Must be kept in sync with equmaczerDriver.c
struct SharedMemoryLayout {
    /// Size of the ring buffer (must match SHARED_MEM_RING_SIZE in driver)
    static let ringSize: UInt32 = 65536

    /// Header offsets in shared memory
    struct Header {
        static let writeIndexOffset: Int = 0                              // _Atomic UInt32
        static let readIndexOffset: Int = 4                               // _Atomic UInt32
        static let frameCountOffset: Int = 8                              // _Atomic UInt32
        static let channelCountOffset: Int = 12                           // UInt32
        static let sampleRateOffset: Int = 16                             // Float64
        static let samplesOffset: Int = 64                                // After padding
    }

    /// Total size of the shared memory region
    static func totalSize(channelCount: UInt32) -> Int {
        return Header.samplesOffset + Int(ringSize) * Int(channelCount) * MemoryLayout<Float>.size
    }
}

// MARK: - Error Types

/// Errors for shared memory capture
enum SharedMemoryCaptureError: Error, LocalizedError, Sendable {
    case sharedMemoryNotAvailable
    case createFailed(Int32)
    case truncateFailed(Int32)
    case mmapFailed(Int32)
    case invalidDevice
    case driverRejectedPath(Int32)

    var errorDescription: String? {
        switch self {
        case .sharedMemoryNotAvailable:
            return "Shared memory not available"
        case .createFailed(let errno):
            return "Failed to create shared memory file: \(errno)"
        case .truncateFailed(let errno):
            return "Failed to set shared memory size: \(errno)"
        case .mmapFailed(let errno):
            return "Failed to map shared memory: \(errno)"
        case .invalidDevice:
            return "Invalid device"
        case .driverRejectedPath(let status):
            switch UInt32(bitPattern: status) {
            case 0x7069643F: return "Driver could not verify the calling process"
            case 0x6F776E3F: return "Another account owns the active audio connection"
            case 0x66696C65: return "Driver rejected the audio file's size, type or permissions"
            case 0x7569643F: return "Driver rejected an audio file owned by a different account"
            case 0x6F70656E: return "Driver could not open the private audio file"
            case 0x6D61703F: return "Driver could not map the private audio file"
            default: break
            }
            return "Driver rejected the private audio file (OSStatus \(status))"
        }
    }
}

// MARK: - Shared Memory Capture

/// Lock-free audio capture from driver via file-based shared memory.
/// The app creates the shared memory file and the driver opens it.
/// This avoids permission issues with POSIX shm_open on macOS.
///
/// - Important: This class is `@unchecked Sendable` because the shared memory
///   is accessed from the audio thread, but all mutations use atomic operations.
final class SharedMemoryCapture: @unchecked Sendable {

    // MARK: - Properties

    /// Static logger for thread-safe access
    private static let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "SharedMemoryCapture")

    /// File descriptor for shared memory (read-only)
    private nonisolated(unsafe) var shmFD: Int32 = -1

    /// Mapped shared memory address
    private nonisolated(unsafe) var shmAddr: UnsafeMutableRawPointer?

    /// Size of mapped region
    private nonisolated(unsafe) var shmSize: Int = 0

    /// Current read position in the ring buffer
    private nonisolated(unsafe) var readIndex: UInt32 = 0

    /// Number of channels (should match driver)
    private let channelCount: UInt32

    /// Path to the shared memory file
    private nonisolated(unsafe) var shmPath: String = ""

    /// Whether shared memory is connected
    private nonisolated(unsafe) var isConnected: Bool = false

    /// First poll after connection - skip accumulated data
    private nonisolated(unsafe) var firstPoll: Bool = true

    // MARK: - Drift Monitoring

    /// Countdown to next log interval check (avoids 64-bit modulo every callback)
    private nonisolated(unsafe) var gapLogCountdown: UInt64 = 0

    /// Gap at the start of the current logging window
    private nonisolated(unsafe) var gapWindowStart: UInt32 = 0

    /// Gap at the end of the current logging window
    private nonisolated(unsafe) var gapWindowEnd: UInt32 = 0

    /// Whether the first valid gap has been recorded in this window
    private nonisolated(unsafe) var gapWindowStarted: Bool = false

    /// Total overflow count for diagnostics
    private nonisolated(unsafe) var totalOverflowCount: UInt32 = 0

    /// Overflow count at last log interval — used to detect new overflows for anomaly logging
    private nonisolated(unsafe) var lastOverflowCount: UInt32 = 0

    // MARK: - Initialization

    /// Creates a new shared memory capture instance.
    /// - Parameter channelCount: Number of audio channels (must match driver)
    init(channelCount: UInt32 = 2) {
        self.channelCount = channelCount
    }

    // MARK: - Lifecycle

    /// Creates and opens a file-based shared memory region.
    /// The caller must set this path on the driver before audio starts.
    /// - Returns: Path to the created shared memory file
    /// - Throws: SharedMemoryCaptureError if creation fails
    @discardableResult
    func create() throws -> String {
        let secureFile = try SecureAudioFile.create()
        let path = secureFile.path
        let fd = secureFile.descriptor

        // Set file size
        let size = SharedMemoryLayout.totalSize(channelCount: channelCount)
        guard ftruncate(fd, off_t(size)) == 0 else {
            let err = errno
            close(fd)
            unlink(path)
            Self.logger.error("Failed to truncate shared memory file: \(err)")
            throw SharedMemoryCaptureError.truncateFailed(err)
        }

        // Map shared memory (read-write so driver can write)
        guard let addr = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0), addr != MAP_FAILED else {
            let err = errno
            close(fd)
            unlink(path)
            Self.logger.error("Failed to map shared memory: \(err)")
            throw SharedMemoryCaptureError.mmapFailed(err)
        }

        // Initialize header
        // Initialise the C11 fields before the mapping is handed to the driver.
        audio_transport_initialize_u32(addr, SharedMemoryLayout.Header.writeIndexOffset, 0)
        audio_transport_initialize_u32(addr, SharedMemoryLayout.Header.readIndexOffset, 0)
        audio_transport_initialize_u32(addr, SharedMemoryLayout.Header.frameCountOffset, 0)

        // Set channel count
        audio_transport_initialize_u32(addr, SharedMemoryLayout.Header.channelCountOffset, channelCount)

        // Set sample rate (default, driver will update)
        audio_transport_initialize_f64(addr, SharedMemoryLayout.Header.sampleRateOffset, 48000)

        // Store values
        self.shmFD = fd
        self.shmAddr = addr
        self.shmSize = size
        self.shmPath = path
        self.isConnected = true
        self.firstPoll = true
        self.readIndex = 0

        Self.logger.info("Created shared memory file: \(path), size: \(size)")

        return path
    }

    /// Gets the path to the shared memory file (for setting on driver).
    /// - Returns: Path if created, empty string otherwise
    func getPath() -> String {
        return shmPath
    }

    /// Disconnects from shared memory and cleans up.
    func disconnect() {
        guard isConnected else { return }

        if let addr = shmAddr {
            munmap(addr, shmSize)
            shmAddr = nil
        }

        if shmFD >= 0 {
            close(shmFD)
            shmFD = -1
        }

        // Remove the file
        let pathToRemove = shmPath
        if !pathToRemove.isEmpty {
            unlink(pathToRemove)
            Self.logger.debug("Removed shared memory file: \(pathToRemove)")
        }

        shmPath = ""
        isConnected = false
        firstPoll = true
        readIndex = 0
        totalOverflowCount = 0
        lastOverflowCount = 0
    }

    // MARK: - Audio Thread Method

    /// Reads available frames from shared memory and deinterleaves directly into destination buffers.
    /// Called from the audio output callback - zero heap allocation.
    /// - Parameters:
    ///   - destBuffers: Array of destination buffers (one per channel), each with capacity for frameCount samples
    ///   - maxFrames: Maximum frames to read (limited by ring buffer availability and destBuffers capacity)
    /// - Returns: Frame count read, or 0 if no data available. Also returns sampleRate and channelCount.
    /// - Note: Real-time safe - no system calls, just memory reads
    @inline(__always)
    func readFramesIntoBuffers(
        destBuffers: [UnsafeMutablePointer<Float>],
        maxFrames: UInt32
    ) -> (frameCount: UInt32, sampleRate: Float64, channelCount: UInt32)? {
        guard isConnected, let shmAddr = shmAddr else { return nil }

        // Read atomic values from shared memory header
        let writeIndex = shmAddr.loadAtomicUInt32(offset: SharedMemoryLayout.Header.writeIndexOffset)
        let frameCount = shmAddr.loadAtomicUInt32(offset: SharedMemoryLayout.Header.frameCountOffset)
        let channelCount = shmAddr.loadAtomicUInt32(offset: SharedMemoryLayout.Header.channelCountOffset)
        let sampleRate = audio_transport_load_f64_acquire(shmAddr, SharedMemoryLayout.Header.sampleRateOffset)

        // The mapped header is external input, even with restricted file access.
        guard maxFrames > 0, writeIndex < SharedMemoryLayout.ringSize,
              channelCount == self.channelCount, sampleRate.isFinite,
              sampleRate >= 8000, sampleRate <= 768000 else { return nil }

        // On first poll, sync read position to write position
        if firstPoll {
            firstPoll = false
            readIndex = writeIndex
            return (0, sampleRate, channelCount)
        }

        // No new data from driver
        guard frameCount > 0 else { return nil }

        // C11 acquire loads above pair with the driver's release publication.

        // Calculate available frames in ring buffer
        let availableFrames: UInt32
        if writeIndex >= readIndex {
            availableFrames = writeIndex &- readIndex
        } else {
            availableFrames = SharedMemoryLayout.ringSize &- readIndex &+ writeIndex
        }

        // Track gap for drift monitoring — lightweight per-callback bookkeeping
        if !gapWindowStarted {
            gapWindowStart = availableFrames
            gapWindowStarted = true
        }
        gapWindowEnd = availableFrames

        // Log only on anomaly: significant drift or overflow
        // Countdown avoids 64-bit modulo division every callback
        if gapLogCountdown == 0 {
            gapLogCountdown = UInt64(48000 * 10 / UInt64(maxFrames))
        }
        gapLogCountdown &-= 1
        if gapLogCountdown == 0 && gapWindowStarted {
            let start = gapWindowStart
            let end = gapWindowEnd
            let delta = Int32(end) - Int32(start)
            // Only log if there's meaningful drift (>1 buffer size) or an overflow occurred
            let previousOverflowCount = lastOverflowCount
            let currentOverflowCount = totalOverflowCount
            if abs(delta) > Int32(maxFrames) || currentOverflowCount > previousOverflowCount {
                // Never call os_log on the real-time audio thread; record anomaly in counter
                totalOverflowCount = currentOverflowCount
            }
            lastOverflowCount = currentOverflowCount
            gapWindowStart = 0
            gapWindowEnd = 0
            gapWindowStarted = false
        }

        // Detect overflow: if more than half the ring is unread, the driver has
        // likely lapped us and the data is corrupted. Resync rather than play garbage.
        // At 768kHz, half the ring (32768 frames) = ~43ms — still beyond normal jitter.
        // At 48kHz, half the ring = ~682ms.
        if availableFrames > SharedMemoryLayout.ringSize / 2 {
            totalOverflowCount &+= 1
            readIndex = writeIndex
            return (0, sampleRate, channelCount)
        }

        // Limit to what we can read and what destBuffers can hold.
        // Note: frameCount is the driver's last IO buffer size, NOT available frames.
        // Using it as a clamp prevents catching up when falling behind, causing
        // steadily growing latency and eventual ring buffer corruption.
        let framesToRead = min(availableFrames, maxFrames)
        guard framesToRead > 0 else { return nil }

        // Verify channel count matches
        guard channelCount == UInt32(destBuffers.count) else { return nil }

        // Get pointer to samples array in shared memory
        let samplesPtr = shmAddr.advanced(by: SharedMemoryLayout.Header.samplesOffset)
            .assumingMemoryBound(to: Float.self)

        // Deinterleave directly from ring buffer into destination buffers.
        // Channel-outer loop gives sequential writes to each destination buffer,
        // which is cache-friendly and allows the compiler to vectorize the inner loop.
        let intChannelCount = Int(channelCount)
        let intFramesToRead = Int(framesToRead)

        if readIndex &+ framesToRead <= SharedMemoryLayout.ringSize {
            // No wrap - single sequential read
            let srcPtr = samplesPtr.advanced(by: Int(readIndex * channelCount))
            for channel in 0..<intChannelCount {
                for frame in 0..<intFramesToRead {
                    destBuffers[channel][frame] = srcPtr[frame * intChannelCount + channel]
                }
            }
        } else {
            // Wrap - two sequential reads
            let firstPart = SharedMemoryLayout.ringSize &- readIndex
            let firstPartInt = Int(firstPart)
            let secondPartInt = Int(framesToRead &- firstPart)

            // First part (from readIndex to end of ring buffer)
            let srcPtr1 = samplesPtr.advanced(by: Int(readIndex * channelCount))
            for channel in 0..<intChannelCount {
                for frame in 0..<firstPartInt {
                    destBuffers[channel][frame] = srcPtr1[frame * intChannelCount + channel]
                }
            }

            // Second part (from start of ring buffer)
            for channel in 0..<intChannelCount {
                for frame in 0..<secondPartInt {
                    destBuffers[channel][firstPartInt + frame] = samplesPtr[frame * intChannelCount + channel]
                }
            }
        }

        // Update read position
        readIndex = (readIndex &+ framesToRead) & (SharedMemoryLayout.ringSize &- 1)

        return (framesToRead, sampleRate, channelCount)
    }

    // MARK: - Drift Diagnostics

    /// Returns drift diagnostic information for logging on pipeline stop.
    func getDriftDiagnostics() -> (startGap: UInt32, endGap: UInt32, deltaGap: Int32, overflows: UInt32) {
        let delta = Int32(gapWindowEnd) - Int32(gapWindowStart)
        return (gapWindowStart, gapWindowEnd, delta, totalOverflowCount)
    }
}

// MARK: - Unsafe Raw Pointer Extensions

private extension UnsafeMutableRawPointer {
    /// Uses the same C11 atomic ABI and acquire ordering as the driver header.
    func loadAtomicUInt32(offset: Int) -> UInt32 {
        audio_transport_load_acquire(self, offset)
    }

    /// Load UInt32 from offset
    func loadUInt32(offset: Int) -> UInt32 {
        let ptr = self.advanced(by: offset).assumingMemoryBound(to: UInt32.self)
        return ptr.pointee
    }

    /// Load Float64 from offset
    func loadFloat64(offset: Int) -> Float64 {
        let ptr = self.advanced(by: offset).assumingMemoryBound(to: Float64.self)
        return ptr.pointee
    }
}
