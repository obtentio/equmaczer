// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import CoreAudio
import Foundation

/// D2: resolves bundle IDs to live Core Audio process object
/// IDs — the currency `CATapDescription` exclusions are paid
/// in. Same permission-free process-object enumeration as
/// ChannelController, without the running filter: the tap
/// excludes the process itself, playing or not. Apps that are
/// not running resolve to nothing (there is nothing to exclude
/// until they exist).
enum ProcessObjectResolver {
    nonisolated static func objectIDs(forBundleIDs wanted: Set<String>) -> [AudioObjectID] {
        guard !wanted.isEmpty else { return [] }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var objects = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }

        var result: [AudioObjectID] = []
        for object in objects {
            var bundleAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var bundleID: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(object, &bundleAddress, 0, nil, &bundleSize, &bundleID) == noErr,
                  let cfBundleID = bundleID?.takeRetainedValue()
            else { continue }
            if wanted.contains(cfBundleID as String) {
                result.append(object)
            }
        }
        return result
    }
}
