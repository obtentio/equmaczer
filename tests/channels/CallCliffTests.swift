// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import CoreAudio
import XCTest
@testable import equmaczer

/// B4: the cliff detector and the microphone choice.
final class CallCliffTests: XCTestCase {
    func testCliffNeedsAllThreeFacts() {
        XCTAssertTrue(CallCliff.isCliff(callLive: true, outputIsBluetooth: true, outputRateHz: 16_000))
        XCTAssertTrue(CallCliff.isCliff(callLive: true, outputIsBluetooth: true, outputRateHz: 24_000))
        XCTAssertFalse(CallCliff.isCliff(callLive: false, outputIsBluetooth: true, outputRateHz: 16_000))
        XCTAssertFalse(CallCliff.isCliff(callLive: true, outputIsBluetooth: false, outputRateHz: 16_000))
        XCTAssertFalse(CallCliff.isCliff(callLive: true, outputIsBluetooth: true, outputRateHz: 48_000))
        XCTAssertFalse(CallCliff.isCliff(callLive: true, outputIsBluetooth: true, outputRateHz: nil))
    }

    private func device(
        uid: String,
        name: String = "Device",
        transport: UInt32
    ) -> AudioDevice {
        AudioDevice(id: 0, uid: uid, name: name, transportType: transport)
    }

    func testBuiltInMicrophonePreferred() {
        let usb = device(uid: "usb", name: "USB Mic", transport: kAudioDeviceTransportTypeUSB)
        let builtIn = device(uid: "builtin", name: "MacBook Microphone", transport: kAudioDeviceTransportTypeBuiltIn)
        let pick = CallCliff.alternativeMicrophone(
            inputDevices: [usb, builtIn],
            currentDefaultInputUID: "headset"
        )
        XCTAssertEqual(pick?.uid, "builtin")
    }

    func testBluetoothAndCurrentDefaultExcluded() {
        let headset = device(uid: "headset", name: "AirPods", transport: kAudioDeviceTransportTypeBluetooth)
        let current = device(uid: "usb", name: "USB Mic", transport: kAudioDeviceTransportTypeUSB)
        let pick = CallCliff.alternativeMicrophone(
            inputDevices: [headset, current],
            currentDefaultInputUID: "usb"
        )
        XCTAssertNil(pick)
    }

    func testVirtualDevicesExcluded() {
        // 'virt' — the constant itself is ambiguous in this target.
        let driver = device(uid: "equmaczer-device", name: "equmaczer", transport: 0x76697274)
        let pick = CallCliff.alternativeMicrophone(
            inputDevices: [driver],
            currentDefaultInputUID: nil
        )
        XCTAssertNil(pick)
    }

    func testFallsBackToAnyRealMicrophone() {
        let usb = device(uid: "usb", name: "USB Mic", transport: kAudioDeviceTransportTypeUSB)
        let pick = CallCliff.alternativeMicrophone(
            inputDevices: [usb],
            currentDefaultInputUID: "headset"
        )
        XCTAssertEqual(pick?.uid, "usb")
    }
    func testRememberedMicrophoneWinsThenFallsBackWhenUnplugged() {
        let usb = device(uid: "usb", transport: kAudioDeviceTransportTypeUSB)
        let builtIn = device(uid: "builtin", transport: kAudioDeviceTransportTypeBuiltIn)
        XCTAssertEqual(CallCliff.preferredMicrophone(candidates: [builtIn, usb], rememberedUID: "usb")?.uid, "usb")
        XCTAssertEqual(CallCliff.preferredMicrophone(candidates: [builtIn], rememberedUID: "usb")?.uid, "builtin")
        XCTAssertNil(CallCliff.preferredMicrophone(candidates: [], rememberedUID: "usb"))
    }
    func testCandidatesIncludeEveryRealNonBluetoothInputExceptHeadset() {
        let usb = device(uid: "usb", transport: kAudioDeviceTransportTypeUSB)
        let builtIn = device(uid: "builtin", transport: kAudioDeviceTransportTypeBuiltIn)
        let headset = device(uid: "headset", transport: kAudioDeviceTransportTypeBluetooth)
        let le = device(uid: "le", transport: kAudioDeviceTransportTypeBluetoothLE)
        XCTAssertEqual(CallCliff.microphoneCandidates(inputDevices: [usb, builtIn, headset, le], excludingUID: "headset").map(\.uid), ["usb", "builtin"])
    }

}
