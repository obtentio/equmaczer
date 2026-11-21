// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
// ProcessTapCapture.swift
// Single-clock-domain macOS CoreAudio Process Tap (CATapDescription) + Aggregate Device capture & output backend.

import AudioToolbox
import CoreAudio
import Foundation
import OSLog

/// Errors for CoreAudio Process Tap (`CATapDescription`) capture.
enum ProcessTapError: Error, LocalizedError, Sendable {
    case outputDeviceUIDNotFound(AudioDeviceID)
    case recordingDeviceUnavailable
    case tapCreationFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case ioProcRegistrationFailed(OSStatus)
    case deviceStartFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .outputDeviceUIDNotFound(let id):
            return "Could not resolve UID for output AudioDeviceID \(id)"
        case .recordingDeviceUnavailable:
            return "The recording driver or microphone is unavailable."
        case .tapCreationFailed(let status):
            return "AudioHardwareCreateProcessTap failed with OSStatus \(status)"
        case .aggregateDeviceCreationFailed(let status):
            return "AudioHardwareCreateAggregateDevice failed with OSStatus \(status)"
        case .ioProcRegistrationFailed(let status):
            return "AudioDeviceCreateIOProcID failed with OSStatus \(status)"
        case .deviceStartFailed(let status):
            return "AudioDeviceStart failed with OSStatus \(status)"
        }
    }
}

/// Captures system audio and renders equalized output in a single hardware clock domain
/// using macOS 14.2+ / 15.0+ `CATapDescription` (`AudioHardwareCreateProcessTap`) and
/// a private aggregate device slaved directly to the physical output DAC's crystal clock.
///
/// Architectural advantages over BlackHole HAL driver loopback:
/// 1. **Zero HAL Driver Installation**: Does not require `/Library/Audio/Plug-Ins/HAL/equmaczer.driver`.
/// 2. **Single Clock Domain**: The aggregate device clock is slaved to `outputDeviceUID`
///    (`kAudioAggregateDeviceClockDeviceKey`), eliminating dual-clock drift and ring buffer latency.
/// 3. **Single IOProc Turnaround**: `inInputData` (tapped system mix) and `outOutputData` (physical DAC)
///    arrive in the same `AudioDeviceIOProc` invocation.
final class ProcessTapCapture: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "ProcessTapCapture")

    /// D2: the tap's one app-state seam. The capture backend is
    /// created deep inside the pipeline, so the store installs
    /// this provider once at launch; it returns the process
    /// object IDs of the listener's never-process apps, resolved
    /// live at tap-build time.
    nonisolated(unsafe) static var userExcludedProcessObjectIDsProvider: (() -> [AudioObjectID])?

    private nonisolated(unsafe) var tapObjectID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private nonisolated(unsafe) var aggregateDeviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private nonisolated(unsafe) var ioProcID: AudioDeviceIOProcID?
    private nonisolated(unsafe) var isRunning: Bool = false

    private var mixerTapIDs: [AudioObjectID] = []
    private(set) var failedChannels: Set<AudioChannel> = []
    private(set) var usesMixer = false
    /// Processes in successfully created mixer taps; nil denotes the global path.
    private(set) var tappedProcessObjectIDs: [AudioObjectID]?

    let tapUUID: UUID = UUID()

    private let hardware: ProcessTapHardwareControlling

    init(hardware: ProcessTapHardwareControlling = ProcessTapHardwareService()) {
        self.hardware = hardware
    }

    deinit {
        stop()
    }

    // MARK: - Configuration Builders (Testable Pure Helpers)

    /// Builds the `CATapDescription` configured to tap all stereo system audio except this process.
    static func makeGlobalStereoTapDescription(
        tapUUID: UUID = UUID(),
        excludedProcessObjectIDs: [AudioObjectID] = []
    ) -> CATapDescription {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcessObjectIDs)
        description.name = "equmaczer System Process Tap"
        description.uuid = tapUUID
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        return description
    }

    /// Builds the CoreAudio aggregate device dictionary slaving the process tap to the physical output device's clock.
    static func makeAggregateDeviceDescription(
        outputDeviceUID: String,
        tapUUID: UUID,
        aggregateUID: String = "com.obtentio.equmaczer.processtap.\(UUID().uuidString)",
        recording: RecordingConfiguration = RecordingConfiguration(),
        driverUID: String? = nil, microphoneUID: String? = nil
    ) -> [String: Any] {
        var devices: [[String: Any]] = [[
            kAudioSubDeviceUIDKey as String: outputDeviceUID,
            kAudioSubDeviceDriftCompensationKey as String: false
        ]]
        if recording.enabled, let driverUID, driverUID != outputDeviceUID {
            devices.append([kAudioSubDeviceUIDKey as String: driverUID,
                            kAudioSubDeviceDriftCompensationKey as String: true])
            if recording.includeMic, let microphoneUID, microphoneUID != outputDeviceUID, microphoneUID != driverUID {
                devices.append([kAudioSubDeviceUIDKey as String: microphoneUID,
                                kAudioSubDeviceDriftCompensationKey as String: true])
            }
        }
        return [
            kAudioAggregateDeviceNameKey as String: "equmaczer Single-Clock Tap Engine",
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceMainSubDeviceKey as String: outputDeviceUID,
            kAudioAggregateDeviceClockDeviceKey as String: outputDeviceUID,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceSubDeviceListKey as String: devices,
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapUIDKey as String: tapUUID.uuidString,
                    kAudioSubTapDriftCompensationKey as String: true
                ]
            ]
        ]
    }

    // MARK: - Lifecycle

    /// Includes only this channel's process objects; never a global exclusion tap.
    static func makeChannelTapDescription(tapUUID: UUID, processObjectIDs: [AudioObjectID], name: String) -> CATapDescription {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.name = name
        description.uuid = tapUUID
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        return description
    }

    /// Same DAC clock and Core Audio resampling policy as the global path.
    static func makeMixerAggregateDescription(outputDeviceUID: String, tapUUIDs: [UUID],
        recording: RecordingConfiguration = RecordingConfiguration(), driverUID: String? = nil, microphoneUID: String? = nil) -> [String: Any] {
        var description = makeAggregateDeviceDescription(outputDeviceUID: outputDeviceUID, tapUUID: tapUUIDs[0],
            recording: recording, driverUID: driverUID, microphoneUID: microphoneUID)
        description[kAudioAggregateDeviceTapListKey as String] = tapUUIDs.map {
            [kAudioSubTapUIDKey as String: $0.uuidString,
             kAudioSubTapDriftCompensationKey as String: true] as [String: Any]
        }
        return description
    }

    /// Called before callbacks start. A partial failure keeps healthy taps;
    /// only an entirely unavailable tap set falls back to the stage path.
    func startMixer(outputDeviceID: AudioDeviceID, context: RenderCallbackContext,
                    mixer: ChannelMixer, assignments: [ChannelTapAssignment]) -> Result<Void, ProcessTapError> {
        guard !isRunning else { return .success(()) }
        failedChannels.removeAll()
        let ownID = hardware.currentProcessObjectID()
        // Idle assignments must not add empty taps to the aggregate.
        let assignments = assignments.filter { $0.objectIDs.contains { $0 != ownID } }
        guard !assignments.isEmpty else { return start(outputDeviceID: outputDeviceID, context: context) }
        guard let uid = hardware.deviceUID(outputDeviceID) else {
            return .failure(.outputDeviceUIDNotFound(outputDeviceID))
        }
        guard assignments.filter({ $0.bundleID != nil }).count <= ChannelMixer.maximumAppSlots else {
            return .failure(.tapCreationFailed(kAudioHardwareUnspecifiedError))
        }
        guard let recordingDevices = prepareRecording(outputDeviceID: outputDeviceID, context: context) else {
            return .failure(.recordingDeviceUnavailable)
        }
        guard !context.recordingConfiguration.enabled || ownID != nil else {
            return .failure(.recordingDeviceUnavailable)
        }
        var uuids: [UUID] = []
        var slots: [ChannelMixerSlot] = []
        var tappedProcesses: [AudioObjectID] = []
        for assignment in assignments {
            let slot: ChannelMixerSlot
            if let bundleID = assignment.bundleID {
                guard let appSlot = mixer.appSlot(for: bundleID) else {
                    stop()
                    return .failure(.tapCreationFailed(kAudioHardwareUnspecifiedError))
                }
                slot = appSlot
            } else { slot = mixer.slot(for: assignment.channel) }
            let uuid = UUID()
            let description = Self.makeChannelTapDescription(tapUUID: uuid,
                processObjectIDs: assignment.objectIDs.filter { $0 != ownID }, name: "equmaczer · \(assignment.bundleID ?? assignment.channel.displayName)")
            var id = AudioObjectID(kAudioObjectUnknown)
            let status = hardware.createTap(description, &id)
            if status != noErr || id == kAudioObjectUnknown {
                if id != kAudioObjectUnknown { hardware.destroyTap(id) }
                failedChannels.insert(assignment.channel)
                slot.failed.store(true, ordering: .releasing)
                Self.logger.error("Channel tap failed: \(assignment.channel.displayName), OSStatus \(status)")
            } else {
                slot.failed.store(false, ordering: .releasing)
                tappedProcesses.append(contentsOf: description.processes)
                mixerTapIDs.append(id)
                uuids.append(uuid)
                slots.append(slot)
            }
        }
        guard !uuids.isEmpty else {
            if assignments.contains(where: { $0.bundleID != nil }) {
                stop()
                return .failure(.tapCreationFailed(kAudioHardwareUnspecifiedError))
            }
            return start(outputDeviceID: outputDeviceID, context: context)
        }
        let description = Self.makeMixerAggregateDescription(outputDeviceUID: uid, tapUUIDs: uuids,
            recording: context.recordingConfiguration, driverUID: recordingDevices.driver, microphoneUID: recordingDevices.mic)
        let aggregateStatus = hardware.createAggregate(description as CFDictionary, &aggregateDeviceID)
        guard aggregateStatus == noErr, aggregateDeviceID != kAudioObjectUnknown else {
            stop()
            return .failure(.aggregateDeviceCreationFailed(aggregateStatus))
        }
        // Physical device input channels precede taps in the aggregate. Never
        // mistake a built-in microphone stream for the first channel tap.
        context.mixer = mixer
        context.mixerTapSlots = slots
        context.useTapInputBuffers()
        mixer.activate(assignments: assignments)
        let pointer = Unmanaged.passUnretained(context).toOpaque()
        let procStatus = hardware.createIOProc(aggregateDeviceID, Self.mixerIOProc, pointer, &ioProcID)
        guard procStatus == noErr, let proc = ioProcID else {
            stop()
            return .failure(.ioProcRegistrationFailed(procStatus))
        }
        let streamStatus = hardware.configureStreams(aggregateDeviceID, proc, context: context)
        guard streamStatus == noErr else {
            stop()
            return .failure(.ioProcRegistrationFailed(streamStatus))
        }
        let startStatus = hardware.start(aggregateDeviceID, proc)
        guard startStatus == noErr else {
            stop()
            return .failure(.deviceStartFailed(startStatus))
        }
        tappedProcessObjectIDs = Array(Set(tappedProcesses)).sorted()
        usesMixer = true
        isRunning = true
        return .success(())
    }

    static func inputChannelCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeInput) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        let list = memory.assumingMemoryBound(to: AudioBufferList.self)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, list) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// Starts the single-clock process tap + aggregate device IOProc pipeline.
    func start(
        outputDeviceID: AudioDeviceID,
        context: RenderCallbackContext
    ) -> Result<Void, ProcessTapError> {
        guard !isRunning else { return .success(()) }

        guard let outputUID = hardware.deviceUID(outputDeviceID) else {
            return .failure(.outputDeviceUIDNotFound(outputDeviceID))
        }

        guard let recordingDevices = prepareRecording(outputDeviceID: outputDeviceID, context: context) else {
            return .failure(.recordingDeviceUnavailable)
        }
        let ownProcessObjectID = hardware.currentProcessObjectID()
        // A recording feed must fail closed if we cannot exclude our own output.
        guard !context.recordingConfiguration.enabled || ownProcessObjectID != nil else {
            return .failure(.recordingDeviceUnavailable)
        }
        // D2: the listener's never-process list joins our own
        // process in the tap's exclusions — excluded processes
        // are never tapped, so their sound passes through
        // untouched and never waits on this app's processing.
        let userExcluded = Self.userExcludedProcessObjectIDsProvider?() ?? []
        let excluded = (ownProcessObjectID.map { [$0] } ?? []) + userExcluded
        let tapDesc = Self.makeGlobalStereoTapDescription(
            tapUUID: tapUUID,
            excludedProcessObjectIDs: excluded
        )

        var createdTapID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = hardware.createTap(tapDesc, &createdTapID)
        guard tapStatus == noErr, createdTapID != AudioObjectID(kAudioObjectUnknown) else {
            Self.logger.error("AudioHardwareCreateProcessTap failed: \(tapStatus)")
            return .failure(.tapCreationFailed(tapStatus))
        }
        self.tapObjectID = createdTapID

        let aggDict = Self.makeAggregateDeviceDescription(
            outputDeviceUID: outputUID,
            tapUUID: tapUUID, recording: context.recordingConfiguration,
            driverUID: recordingDevices.driver, microphoneUID: recordingDevices.mic
        )
        var createdAggID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
        let aggStatus = hardware.createAggregate(aggDict as CFDictionary, &createdAggID)
        guard aggStatus == noErr, createdAggID != AudioObjectID(kAudioObjectUnknown) else {
            hardware.destroyTap(createdTapID)
            self.tapObjectID = AudioObjectID(kAudioObjectUnknown)
            Self.logger.error("AudioHardwareCreateAggregateDevice failed: \(aggStatus)")
            return .failure(.aggregateDeviceCreationFailed(aggStatus))
        }
        self.aggregateDeviceID = createdAggID

        let contextPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(context).toOpaque())
        var createdIOProcID: AudioDeviceIOProcID?
        context.useTapInputBuffers()
        let procStatus = hardware.createIOProc(
            createdAggID,
            Self.singleClockIOProc,
            contextPtr,
            &createdIOProcID
        )
        guard procStatus == noErr, let validProcID = createdIOProcID else {
            hardware.destroyAggregate(createdAggID)
            hardware.destroyTap(createdTapID)
            self.aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
            self.tapObjectID = AudioObjectID(kAudioObjectUnknown)
            return .failure(.ioProcRegistrationFailed(procStatus))
        }
        self.ioProcID = validProcID

        let streamStatus = hardware.configureStreams(createdAggID, validProcID, context: context)
        guard streamStatus == noErr else {
            stop()
            return .failure(.ioProcRegistrationFailed(streamStatus))
        }
        let startStatus = hardware.start(createdAggID, validProcID)
        guard startStatus == noErr else {
            hardware.destroyIOProc(createdAggID, validProcID)
            hardware.destroyAggregate(createdAggID)
            hardware.destroyTap(createdTapID)
            self.ioProcID = nil
            self.aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
            self.tapObjectID = AudioObjectID(kAudioObjectUnknown)
            return .failure(.deviceStartFailed(startStatus))
        }

        isRunning = true
        Self.logger.info("ProcessTapCapture started on output device UID \(outputUID)")
        return .success(())
    }

    /// Stops and tears down the aggregate device and process tap.
    func stop() {
        if let procID = ioProcID, aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            if isRunning {
                hardware.stop(aggregateDeviceID, procID)
            }
            hardware.destroyIOProc(aggregateDeviceID, procID)
            ioProcID = nil
        }
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            hardware.destroyAggregate(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapObjectID != AudioObjectID(kAudioObjectUnknown) {
            hardware.destroyTap(tapObjectID)
            tapObjectID = AudioObjectID(kAudioObjectUnknown)
        }
        for id in mixerTapIDs { hardware.destroyTap(id) }
        mixerTapIDs.removeAll()
        usesMixer = false
        tappedProcessObjectIDs = nil
        isRunning = false
    }

    /// Testable callback body. All tables and buffers are installed before
    /// AudioDeviceStart and retained until after AudioDeviceStop.
    static func renderMixer(context: RenderCallbackContext, input: UnsafePointer<AudioBufferList>,
                            output: UnsafeMutablePointer<AudioBufferList>) {
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        guard let first = outputs.first else { return }
        let requested = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * max(1, Int(first.mNumberChannels)))
        RenderCallbackContext.zeroFill(output, frameCount: UInt32(requested))
        guard !context.isStopping, requested > 0, let mixer = context.mixer else { return }
        let frames = min(requested, Int(context.maxFrameCount))
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        var receivedFrames = 0
        // Flatten stream channels so both interleaved and planar stereo taps
        // map identically, including physical input channels before the taps.
        for index in context.mixerTapSlots.indices {
            let leftChannel = context.mixerInputChannelOffset + index * 2
            var base = 0
            var left: UnsafePointer<Float>?
            var right: UnsafePointer<Float>?
            var leftStride = 1
            var rightStride = 1
            var available = frames
            for buffer in inputs {
                let channels = Int(buffer.mNumberChannels)
                if channels > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                    if leftChannel >= base && leftChannel < base + channels {
                        left = UnsafePointer(data.advanced(by: leftChannel - base))
                        leftStride = channels
                        available = min(available, Int(buffer.mDataByteSize) / (4 * channels))
                    }
                    if leftChannel + 1 >= base && leftChannel + 1 < base + channels {
                        right = UnsafePointer(data.advanced(by: leftChannel + 1 - base))
                        rightStride = channels
                        available = min(available, Int(buffer.mDataByteSize) / (4 * channels))
                    }
                }
                base += channels
            }
            let slot = context.mixerTapSlots[index]
            if let left, let right, available > 0,
               !slot.failed.load(ordering: .acquiring) {
                slot.write(left: left, right: right, stride: leftStride, rightStride: rightStride, frameCount: available)
                receivedFrames = max(receivedFrames, available)
            }
        }
        context.noteInputFrames(receivedFrames)
        mixer.process(frameCount: UInt32(frames), treated: context.processingMode == 1)
        for channel in 0..<min(2, Int(context.channelCount)) {
            context.inputSampleBuffers[channel].update(from: mixer.output(channel), count: frames)
        }
        context.meterInput(frameCount: frames)
        if context.processingMode != 0 {
            context.applyGain(to: context.inputSampleBuffers, frameCount: UInt32(frames),
                              currentGain: &context.inputGainLinear, targetGain: context.getTargetInputGain())
        }
        if context.processingMode == 1 {
            context.measureLoudnessIn(frameCount: UInt32(frames))
            context.processEQ(frameCount: UInt32(frames), skipChannelLayer: true)
        } else if context.processingMode == 2 {
            context.applyBypassMatchGain(frameCount: UInt32(frames))
        }
        if context.processingMode != 1 {
            mixer.addSkipped(left: context.inputSampleBuffers[0], right: context.inputSampleBuffers[1], frameCount: frames)
        }
        context.measureLoudnessOut(frameCount: UInt32(frames))
        let planarOutput = context.prepareInputBufferList(frameCount: UInt32(frames))
        if context.processingMode != 0 {
            context.applyOutputGainWithSoftStart(to: planarOutput, frameCount: UInt32(frames))
        }
        context.updateOutputMeters(from: planarOutput, frameCount: UInt32(frames))
        writeFinalOutput(context: context, input: input, output: output, frames: frames)
    }

    private static let mixerIOProc: AudioDeviceIOProc = { _, _, input, _, output, _, data in
        guard let data else { return noErr }
        let context = Unmanaged<RenderCallbackContext>.fromOpaque(data).takeUnretainedValue()
        renderMixer(context: context, input: input, output: output)
        return noErr
    }

    // MARK: - Real-Time Single-Clock IOProc (Zero Allocation, Zero Locks)

    private static let singleClockIOProc: AudioDeviceIOProc = { _, _, input, _, output, _, data in
        guard let data else { return noErr }
        renderSingle(context: Unmanaged<RenderCallbackContext>.fromOpaque(data).takeUnretainedValue(),
                     input: input, output: output)
        return noErr
    }

    static func renderSingle(context: RenderCallbackContext, input: UnsafePointer<AudioBufferList>,
                             output: UnsafeMutablePointer<AudioBufferList>) {
        guard let first = UnsafeMutableAudioBufferListPointer(output).first else { return }
        let requested = Int(first.mDataByteSize) / (4 * max(1, Int(first.mNumberChannels)))
        RenderCallbackContext.zeroFill(output, frameCount: UInt32(requested))
        guard !context.isStopping, requested > 0 else { return }
        let frames = min(requested, Int(context.maxFrameCount))
        for channel in 0..<min(2, Int(context.channelCount)) {
            let dest = context.inputSampleBuffers[channel]
            if let resolved = RecordingFeed.resolveChannel(input, channel: context.mixerInputChannelOffset + channel) {
                let copyCount = min(frames, resolved.availableFrames)
                if resolved.stride == 1 {
                    memcpy(dest, resolved.base, copyCount * MemoryLayout<Float>.size)
                } else {
                    for frame in 0..<copyCount {
                        dest[frame] = resolved.base[frame * resolved.stride]
                    }
                }
                if copyCount < frames {
                    memset(dest.advanced(by: copyCount), 0, (frames - copyCount) * MemoryLayout<Float>.size)
                }
            } else {
                memset(dest, 0, frames * MemoryLayout<Float>.size)
            }
        }
        // The IOProc running proves the route alive (as before card 10): a warming tap hands
        // empty buffers for a moment, and counting only filled frames tripped the 1.2 s proof.
        context.noteInputFrames(frames)
        context.meterInput(frameCount: frames)
        if context.processingMode != 0 {
            context.applyGain(to: context.inputSampleBuffers, frameCount: UInt32(frames),
                currentGain: &context.inputGainLinear, targetGain: context.getTargetInputGain())
        }
        if context.processingMode == 1 {
            context.measureLoudnessIn(frameCount: UInt32(frames))
            context.processEQ(frameCount: UInt32(frames))
        } else if context.processingMode == 2 {
            context.applyBypassMatchGain(frameCount: UInt32(frames))
        }
        context.measureLoudnessOut(frameCount: UInt32(frames))
        let planar = context.prepareInputBufferList(frameCount: UInt32(frames))
        if context.processingMode != 0 {
            context.applyOutputGainWithSoftStart(to: planar, frameCount: UInt32(frames))
        }
        context.updateOutputMeters(from: planar, frameCount: UInt32(frames))
        writeFinalOutput(context: context, input: input, output: output, frames: frames)
    }

    private static func writeFinalOutput(context: RenderCallbackContext, input: UnsafePointer<AudioBufferList>,
                                         output: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        let feed = context.recordingFeed
        let sources = context.outputBufferPointers
        guard sources.count >= 2 else { return }
        feed.mix(finalLeft: sources[0], finalRight: sources[1], input: input, frames: frames)
        var base = 0
        for buffer in UnsafeMutableAudioBufferListPointer(output) {
            let channels = Int(buffer.mNumberChannels)
            if channels > 0, let destination = buffer.mData?.assumingMemoryBound(to: Float.self) {
                let count = min(frames, Int(buffer.mDataByteSize) / (4 * channels))
                for channel in 0..<channels {
                    let absolute = base + channel
                    if context.hardwareOutputChannelCount == 1 && absolute == 0 {
                        // Mono output (e.g. Bluetooth HFP/SCO): downmix L+R rather than dropping Right.
                        let leftSrc = sources[0]
                        let rightSrc = sources[1]
                        for frame in 0..<count {
                            destination[frame * channels + channel] = 0.5 * (leftSrc[frame] + rightSrc[frame])
                        }
                    } else if absolute < min(2, context.hardwareOutputChannelCount) {
                        for frame in 0..<count { destination[frame * channels + channel] = sources[absolute][frame] }
                    } else if let offset = feed.driverOutputOffset, absolute >= offset, absolute < offset + 2 {
                        if feed.enabled.load(ordering: .acquiring) {
                            let source = absolute == offset ? feed.left : feed.right
                            for frame in 0..<count { destination[frame * channels + channel] = source[frame] }
                        }
                    }
                }
            }
            base += channels
        }
    }

    /// Control-side topology. Driver inputs are skipped, never treated as taps.
    private func prepareRecording(outputDeviceID: AudioDeviceID, context: RenderCallbackContext) -> (driver: String?, mic: String?)? {
        let configuration = context.recordingConfiguration
        let feed = context.recordingFeed
        feed.enabled.store(false, ordering: .releasing)
        feed.includeMic.store(false, ordering: .releasing)
        feed.driverOutputOffset = nil
        feed.micInputOffset = 0
        feed.micChannelCount = 0
        let physicalInputs = hardware.inputChannelCount(outputDeviceID)
        context.mixerInputChannelOffset = physicalInputs
        context.hardwareOutputChannelCount = max(1, hardware.outputChannelCount(outputDeviceID))
        guard configuration.enabled else { return (nil, nil) }
        guard let driver = hardware.deviceID(forUID: DRIVER_DEVICE_UID), driver != outputDeviceID else { return nil }
        feed.driverOutputOffset = context.hardwareOutputChannelCount
        context.mixerInputChannelOffset += hardware.inputChannelCount(driver)
        var micUID: String?
        if configuration.includeMic {
            guard let mic = configuration.microphoneUID.flatMap({ hardware.deviceID(forUID: $0) }) ??
                    (configuration.microphoneUID == nil ? hardware.defaultInputDeviceID() : nil),
                  let uid = hardware.deviceUID(mic), !uid.hasPrefix("equmaczer"),
                  hardware.inputChannelCount(mic) > 0 else { return nil }
            micUID = uid
            feed.micChannelCount = hardware.inputChannelCount(mic)
            feed.micInputOffset = mic == outputDeviceID ? 0 : context.mixerInputChannelOffset
            if mic != outputDeviceID { context.mixerInputChannelOffset += feed.micChannelCount }
        }
        feed.includeMic.store(configuration.includeMic, ordering: .releasing)
        feed.enabled.store(true, ordering: .releasing)
        return (DRIVER_DEVICE_UID, micUID)
    }

    // MARK: - CoreAudio Property Queries

    static func queryDeviceUID(deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &uid
        )
        guard status == noErr, let cfUID = uid?.takeRetainedValue() else {
            return nil
        }
        return cfUID as String
    }

    static func queryCurrentProcessAudioObjectID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = getpid()
        var objectID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &size,
            &objectID
        )
        guard status == noErr, objectID != AudioObjectID(kAudioObjectUnknown) else {
            return nil
        }
        return objectID
    }
}
