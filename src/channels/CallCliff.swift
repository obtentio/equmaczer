// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import CoreAudio
import Foundation

/// The call cliff (B4), as pure decisions. The mechanism: while
/// any app uses a Bluetooth headset as an input, macOS holds it in
/// the hands-free profile — output collapses to voice rates. The
/// detector's ground truth is the output rate itself: if the
/// headset is not the call's microphone, HFP never engages and
/// the rate stays high, so the conjunction below cannot fire on a
/// healthy call.
enum CallCliff {
    /// The highest hands-free rate (super-wideband). A2DP music
    /// rates are 44.1 kHz and up.
    static let hfpCeilingHz = 24_000.0

    static func isBluetooth(_ device: AudioDevice) -> Bool {
        device.isBluetooth
    }

    static func isCliff(
        callLive: Bool,
        outputIsBluetooth: Bool,
        outputRateHz: Double?
    ) -> Bool {
        callLive
            && outputIsBluetooth
            && (outputRateHz ?? .greatestFiniteMagnitude) <= hfpCeilingHz
    }

    /// The microphone the rescue switches to: a real, non-Bluetooth
    /// input that isn't already the default — the built-in
    /// microphone preferred, since it is always there.
    static func alternativeMicrophone(
        inputDevices: [AudioDevice],
        currentDefaultInputUID: String?
    ) -> AudioDevice? {
        let candidates = microphoneCandidates(inputDevices: inputDevices, excludingUID: currentDefaultInputUID)
        return candidates.first(where: { $0.isBuiltIn }) ?? candidates.first
    }
    static func microphoneCandidates(inputDevices: [AudioDevice], excludingUID: String?) -> [AudioDevice] {
        inputDevices.filter { $0.isRealDevice && !isBluetooth($0) && $0.uid != excludingUID }
    }

    static func preferredMicrophone(candidates: [AudioDevice], rememberedUID: String?) -> AudioDevice? {
        candidates.first { $0.uid == rememberedUID } ?? candidates.first { $0.isBuiltIn } ?? candidates.first
    }

}
