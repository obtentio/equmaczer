// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
// DirectDeviceOutput.swift
// Direct CoreAudio AudioDeviceCreateIOProcID hardware output backend (TCC-free output-only path).

import AudioToolbox
import CoreAudio
import Foundation
import OSLog

/// Direct `AudioDeviceCreateIOProcID` hardware output manager.
///
/// Bypasses `AudioComponentInstanceNew(kAudioUnitSubType_HALOutput)` for output-only playback,
/// avoiding the macOS TCC microphone permission prompt triggered by dual-purpose `HALOutput`
/// AudioUnits (see `docs/plans/TCC-Permission-Architecture.md`).
final class DirectDeviceOutput: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "DirectDeviceOutput")

    private(set) var deviceID: AudioDeviceID = 0
    private nonisolated(unsafe) var ioProcID: AudioDeviceIOProcID?
    private nonisolated(unsafe) var isRunning: Bool = false

    init() {}

    deinit {
        _ = stop()
    }

    /// Queries the nominal sample rate and output channel count of `deviceID`.
    static func queryOutputFormat(deviceID: AudioDeviceID) -> (sampleRate: Double, channels: UInt32)? {
        var rateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Float64 = 0
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(deviceID, &rateAddress, 0, nil, &rateSize, &sampleRate) == noErr,
              sampleRate > 0 else {
            return nil
        }

        var streamAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var configSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &configSize) == noErr,
              configSize >= UInt32(MemoryLayout<AudioBufferList>.size) else {
            return (sampleRate, 2)
        }

        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(configSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPtr.deallocate() }
        let ablPtr = rawPtr.assumingMemoryBound(to: AudioBufferList.self)

        guard AudioObjectGetPropertyData(deviceID, &streamAddress, 0, nil, &configSize, ablPtr) == noErr else {
            return (sampleRate, 2)
        }

        let buffers = UnsafeMutableAudioBufferListPointer(ablPtr)
        var totalChannels: UInt32 = 0
        for buf in buffers {
            totalChannels += buf.mNumberChannels
        }
        return (sampleRate, max(2, totalChannels))
    }

    /// Registers an `AudioDeviceIOProc` directly on `deviceID` and starts hardware output.
    func start(
        deviceID: AudioDeviceID,
        ioProc: @escaping AudioDeviceIOProc,
        clientData: UnsafeMutableRawPointer
    ) -> Result<Void, HALIOError> {
        guard !isRunning else { return .success(()) }
        self.deviceID = deviceID

        var createdProcID: AudioDeviceIOProcID?
        let createStatus = AudioDeviceCreateIOProcID(deviceID, ioProc, clientData, &createdProcID)
        guard createStatus == noErr, let validProcID = createdProcID else {
            Self.logger.error("AudioDeviceCreateIOProcID failed on device \(deviceID): \(createStatus)")
            return .failure(.callbackRegistrationFailed(scope: "directOutput", createStatus))
        }
        self.ioProcID = validProcID

        let startStatus = AudioDeviceStart(deviceID, validProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(deviceID, validProcID)
            self.ioProcID = nil
            Self.logger.error("AudioDeviceStart failed on device \(deviceID): \(startStatus)")
            return .failure(.startFailed(startStatus))
        }

        isRunning = true
        return .success(())
    }

    /// Stops and unregisters the direct `AudioDeviceIOProcID`.
    func stop() -> Result<Void, HALIOError> {
        guard let procID = ioProcID, deviceID != 0 else {
            isRunning = false
            return .success(())
        }
        var lastError: HALIOError?
        if isRunning {
            let stopStatus = AudioDeviceStop(deviceID, procID)
            if stopStatus != noErr {
                lastError = .stopFailed(stopStatus)
            }
        }
        AudioDeviceDestroyIOProcID(deviceID, procID)
        ioProcID = nil
        isRunning = false
        if let err = lastError {
            return .failure(err)
        }
        return .success(())
    }
}
