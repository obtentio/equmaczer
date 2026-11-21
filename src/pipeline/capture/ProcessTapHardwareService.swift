import CoreAudio
import Foundation

/// Control-side Core Audio lifecycle boundary. Never called by a render callback.
protocol ProcessTapHardwareControlling {
    func deviceUID(_ device: AudioDeviceID) -> String?
    func outputChannelCount(_ device: AudioDeviceID) -> Int
    func deviceID(forUID uid: String) -> AudioDeviceID?
    func defaultInputDeviceID() -> AudioDeviceID?
    func inputChannelCount(_ device: AudioDeviceID) -> Int
    func currentProcessObjectID() -> AudioObjectID?
    /// nil checks all processes; an empty set checks none. Excludes our own output.
    func isAnyProcessRunningOutput(processObjectIDs: [AudioObjectID]?) -> Bool
    func createTap(_ description: CATapDescription, _ id: inout AudioObjectID) -> OSStatus
    func destroyTap(_ id: AudioObjectID)
    func createAggregate(_ description: CFDictionary, _ id: inout AudioObjectID) -> OSStatus
    func destroyAggregate(_ id: AudioObjectID)
    func createIOProc(_ device: AudioDeviceID, _ callback: AudioDeviceIOProc,
                      _ context: UnsafeMutableRawPointer, _ id: inout AudioDeviceIOProcID?) -> OSStatus
    func destroyIOProc(_ device: AudioDeviceID, _ id: AudioDeviceIOProcID)
    func configureStreams(_ device: AudioDeviceID, _ id: AudioDeviceIOProcID, context: RenderCallbackContext) -> OSStatus
    func start(_ device: AudioDeviceID, _ id: AudioDeviceIOProcID) -> OSStatus
    func stop(_ device: AudioDeviceID, _ id: AudioDeviceIOProcID)
}

final class ProcessTapHardwareService: ProcessTapHardwareControlling {
    func outputChannelCount(_ device: AudioDeviceID) -> Int {
        ProcessTapCapture.inputChannelCount(deviceID: device, scope: kAudioDevicePropertyScopeOutput)
    }

    func deviceUID(_ device: AudioDeviceID) -> String? { ProcessTapCapture.queryDeviceUID(deviceID: device) }
    func inputChannelCount(_ device: AudioDeviceID) -> Int { ProcessTapCapture.inputChannelCount(deviceID: device) }
    func currentProcessObjectID() -> AudioObjectID? { ProcessTapCapture.queryCurrentProcessAudioObjectID() }
    func isAnyProcessRunningOutput(processObjectIDs: [AudioObjectID]?) -> Bool {
        let objects: [AudioObjectID]
        if let processObjectIDs {
            objects = processObjectIDs
        } else {
            let system = AudioObjectID(kAudioObjectSystemObject)
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return false }
            var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
            guard !processes.isEmpty,
                  AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return false }
            objects = processes
        }
        let ownID = currentProcessObjectID()
        return objects.contains { object in
            guard object != ownID else { return false }
            var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &running) == noErr && running != 0
        }
    }

    func createTap(_ description: CATapDescription, _ id: inout AudioObjectID) -> OSStatus {
        AudioHardwareCreateProcessTap(description, &id)
    }
    func destroyTap(_ id: AudioObjectID) { AudioHardwareDestroyProcessTap(id) }
    func createAggregate(_ description: CFDictionary, _ id: inout AudioObjectID) -> OSStatus {
        AudioHardwareCreateAggregateDevice(description, &id)
    }
    func destroyAggregate(_ id: AudioObjectID) { AudioHardwareDestroyAggregateDevice(id) }
    func createIOProc(_ device: AudioDeviceID, _ callback: AudioDeviceIOProc,
                      _ context: UnsafeMutableRawPointer, _ id: inout AudioDeviceIOProcID?) -> OSStatus {
        AudioDeviceCreateIOProcID(device, callback, context, &id)
    }
    func destroyIOProc(_ device: AudioDeviceID, _ id: AudioDeviceIOProcID) { AudioDeviceDestroyIOProcID(device, id) }
    /// Disable unused device inputs (including the driver's loopback) and mic outputs.
    /// Disabled streams retain their place in the IOProc ABL with a nil data pointer.
    func configureStreams(_ device: AudioDeviceID, _ id: AudioDeviceIOProcID, context: RenderCallbackContext) -> OSStatus {
        for scope in [kAudioDevicePropertyScopeInput, kAudioDevicePropertyScopeOutput] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                mScope: scope, mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            var status = AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size)
            guard status == noErr else { return status }
            let count = Int(size) / MemoryLayout<AudioStreamID>.size
            if count == 0 { continue }
            var streams = [AudioStreamID](repeating: 0, count: count)
            status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &streams)
            guard status == noErr else { return status }
            let bytes = MemoryLayout<AudioHardwareIOProcStreamUsage>.size + (count - 1) * MemoryLayout<UInt32>.stride
            let memory = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment)
            defer { memory.deallocate() }
            memory.initializeMemory(as: UInt8.self, repeating: 0, count: bytes)
            let usage = memory.assumingMemoryBound(to: AudioHardwareIOProcStreamUsage.self)
            usage.pointee.mIOProc = unsafeBitCast(id, to: UnsafeMutableRawPointer.self)
            usage.pointee.mNumberStreams = UInt32(count)
            var base = 0
            for (index, stream) in streams.enumerated() {
                var format = AudioStreamBasicDescription()
                var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                var formatAddress = AudioObjectPropertyAddress(mSelector: kAudioStreamPropertyVirtualFormat,
                    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                status = AudioObjectGetPropertyData(stream, &formatAddress, 0, nil, &formatSize, &format)
                guard status == noErr else { return status }
                let end = base + Int(format.mChannelsPerFrame)
                let feed = context.recordingFeed
                let used: Bool
                if scope == kAudioDevicePropertyScopeInput {
                    let taps = end > context.mixerInputChannelOffset
                    let mic = feed.includeMic.load(ordering: .acquiring) && base < feed.micInputOffset + feed.micChannelCount && end > feed.micInputOffset
                    used = taps || mic
                } else {
                    let dac = base < context.hardwareOutputChannelCount
                    let driver = feed.driverOutputOffset.map { base < $0 + 2 && end > $0 } ?? false
                    used = dac || driver
                }
                let offset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn)!
                memory.advanced(by: offset).assumingMemoryBound(to: UInt32.self)[index] = used ? 1 : 0
                base = end
            }
            address.mSelector = kAudioDevicePropertyIOProcStreamUsage
            status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(bytes), memory)
            guard status == noErr else { return status }
        }
        return noErr
    }

    func start(_ device: AudioDeviceID, _ id: AudioDeviceIOProcID) -> OSStatus { AudioDeviceStart(device, id) }
    func stop(_ device: AudioDeviceID, _ id: AudioDeviceIOProcID) { AudioDeviceStop(device, id) }

    func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return nil }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return nil }
        return devices.first { deviceUID($0) == uid }
    }
    func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown, let uid = deviceUID(id), !uid.hasPrefix("equmaczer") else { return nil }
        return id
    }
}
