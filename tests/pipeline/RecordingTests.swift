import CoreAudio
import RecordingAllocationProbe
import XCTest
@testable import equmaczer

final class MixerRecordingTests: XCTestCase {
    private func context(mic: Bool = false, mixer: Bool = false) -> RenderCallbackContext {
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
        context.useTapInputBuffers()
        context.processingMode = 0
        context.mixerInputChannelOffset = 3 // unused driver input stereo, then mono mic
        context.recordingFeed.driverOutputOffset = 2
        context.recordingFeed.micInputOffset = 2
        context.recordingFeed.micChannelCount = 1
        context.recordingFeed.enabled.store(true, ordering: .releasing)
        context.recordingFeed.includeMic.store(mic, ordering: .releasing)
        if mixer {
            let mixer = ChannelMixer(maxFrameCount: 64)
            mixer.setActive([.music])
            context.mixer = mixer
            context.mixerTapSlots = [mixer.slot(for: .music)]
        }
        return context
    }

    func testFinalEQAndOutputGainSamplesReachRecordingFeed() {
        for mixer in [false, true] {
            let context = context(mixer: mixer)
            context.processingMode = 1
            context.setTargetOutputGain(0.5)
            let coefficient = SVFCoefficients(biquad: BiquadMath.calculateCoefficients(
                type: .lowShelf, sampleRate: 48000, frequency: 500, q: 0.7, gain: -6))
            for chain in [context.leftEQChains[0], context.rightEQChains[0]] {
                chain.stageFullUpdate(coefficients: [coefficient], bypassFlags: [false], activeBandCount: 1, layerBypass: false)
            }
            let input = RecordingBuffers(channels: [2, 1, 2], frames: 64, values: [99, 99, 0, 0.2, -0.1])
            let output = RecordingBuffers(channels: [2, 2], frames: 64, values: [9, 9, 9, 9])
            for _ in 0..<100 {
                if mixer { ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer) }
                else { ProcessTapCapture.renderSingle(context: context, input: input.pointer, output: output.pointer) }
            }
            for frame in 0..<64 {
                for channel in 0..<2 {
                    XCTAssertEqual(output.sample(0, frame * 2 + channel), output.sample(1, frame * 2 + channel))
                }
            }
            XCTAssertLessThan(abs(output.sample(1, 126)), 0.09) // EQ and output attenuation applied
            XCTAssertGreaterThan(abs(output.sample(1, 126)), 0.001)
            context.recordingFeed.enabled.store(false, ordering: .releasing)
            if mixer { ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer) }
            else { ProcessTapCapture.renderSingle(context: context, input: input.pointer, output: output.pointer) }
            XCTAssertEqual(output.sample(1, 126), 0)
            XCTAssertNotEqual(output.sample(0, 126), 0)
        }
    }

    func testDriverGainPointZeroOneIsCompensatedWithoutClipping() {
        assertRecordingLevel(driverGain: 0.01)
    }

    func testUnityDriverGainLeavesRecordingUnchanged() {
        assertRecordingLevel(driverGain: 1)
    }

    private func assertRecordingLevel(driverGain: Float) {
        for mixer in [false, true] {
            for mic in [false, true] {
                for mode: Int32 in [0, 1, 2] {
                    let context = context(mic: mic, mixer: mixer)
                    context.processingMode = mode
                    context.recordingFeed.compensationGainBits.store((1 / driverGain).bitPattern, ordering: .relaxed)
                    let input = RecordingBuffers(channels: [2, 1, 2], frames: 64, values: [99, 99, 0.3, 0.2, -0.1])
                    let output = RecordingBuffers(channels: [2, 2], frames: 64, values: [9, 9, 9, 9])
                    for _ in 0..<100 {
                        if mixer { ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer) }
                        else { ProcessTapCapture.renderSingle(context: context, input: input.pointer, output: output.pointer) }
                    }
                    for frame in 0..<64 {
                        for channel in 0..<2 {
                            let final = output.sample(0, frame * 2 + channel)
                            let expected = final + (mic ? Float(0.3) : 0)
                            let feed = output.sample(1, frame * 2 + channel)
                            XCTAssertEqual(feed, expected / driverGain, accuracy: 1e-5)
                            XCTAssertEqual(feed * driverGain, expected, accuracy: 1e-6)
                        }
                    }
                    // Only the driver feed is pre-boosted; the DAC remains at final level.
                    XCTAssertEqual(output.sample(0, 126), 0.2, accuracy: 1e-6)
                    if driverGain == 0.01 { XCTAssertGreaterThan(output.sample(1, 126), 1) }
                    context.recordingFeed.enabled.store(false, ordering: .releasing)
                    if mixer { ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer) }
                    else { ProcessTapCapture.renderSingle(context: context, input: input.pointer, output: output.pointer) }
                    XCTAssertEqual(output.sample(1, 126), 0)
                }
            }
        }
    }

    func testMonoMicOnlyEntersRecordingAndDriverInputNeverEntersEitherFeed() {
        for mixer in [false, true] {
            let context = context(mic: true, mixer: mixer)
            let input = RecordingBuffers(channels: [2, 1, 2], frames: 64, values: [99, 99, 0.3, 0.1, -0.2])
            let output = RecordingBuffers(channels: [2, 2, 2], frames: 64, values: [9, 9, 9, 9, 9, 9])
            if mixer { ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer) }
            else { ProcessTapCapture.renderSingle(context: context, input: input.pointer, output: output.pointer) }
            XCTAssertEqual(output.sample(0, 126), 0.1, accuracy: 1e-6)
            XCTAssertEqual(output.sample(0, 127), -0.2, accuracy: 1e-6)
            XCTAssertEqual(output.sample(1, 126), 0.4, accuracy: 1e-6)
            XCTAssertEqual(output.sample(1, 127), 0.1, accuracy: 1e-6)
            XCTAssertEqual(output.sample(2, 126), 0) // mic's own output stays silent
        }
    }

    func testPlanarStereoMicAndMultichannelDACOffsets() {
        let context = context(mic: true)
        context.hardwareOutputChannelCount = 4
        context.recordingFeed.driverOutputOffset = 4
        context.recordingFeed.micChannelCount = 2
        context.mixerInputChannelOffset = 4
        let input = RecordingBuffers(channels: [1, 1, 1, 1, 1, 1], frames: 64, values: [99, 99, 0.3, -0.4, 0.1, 0.2])
        let output = RecordingBuffers(channels: [4, 1, 1], frames: 64, values: [9, 9, 9, 9, 9, 9])
        ProcessTapCapture.renderSingle(context: context, input: input.pointer, output: output.pointer)
        XCTAssertEqual(output.sample(0, 0), 0.1, accuracy: 1e-6)
        XCTAssertEqual(output.sample(0, 1), 0.2, accuracy: 1e-6)
        XCTAssertEqual(output.sample(0, 2), 0)
        XCTAssertEqual(output.sample(1, 63), 0.4, accuracy: 1e-6)
        XCTAssertEqual(output.sample(2, 63), -0.2, accuracy: 1e-6)
    }

    func testNoAllocationsInTenThousandCallbacksWithBothSwitchesOn() throws {
        #if DEBUG
        // Unoptimised Swift standard-library iterators themselves allocate.
        // Count real mallocs in the shipping configuration, rather than hiding
        // those allocations or confusing stable pointers with an allocation count.
        throw XCTSkip("Run -c release --filter MixerRecordingTests/testNoAllocations for the malloc-event assertion")
        #else
        for mixer in [false, true] {
            let context = context(mic: true, mixer: mixer)
            context.processingMode = 1
            context.recordingFeed.compensationGainBits.store(Float(100).bitPattern, ordering: .relaxed)
            let input = RecordingBuffers(channels: [2, 1, 2], frames: 64, values: [99, 99, 0.3, 0.1, -0.2])
            let output = RecordingBuffers(channels: [2, 2], frames: 64, values: [9, 9, 9, 9])
            // Warm runtime metadata and lazy DSP initialisation before measurement.
            for _ in 0..<10 {
                if mixer { ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer) }
                else { ProcessTapCapture.renderSingle(context: context, input: input.pointer, output: output.pointer) }
            }
            XCTAssertTrue(recording_allocations_begin(), "Darwin malloc logger must be available")
            recording_allocation_probe_check()
            XCTAssertGreaterThan(recording_allocations_end(), 0, "Probe must detect actual mallocs")
            guard recording_allocations_begin() else { XCTFail("Allocation probe unavailable"); return }
            var callback = 0
            while callback < 10_000 {
                callback += 1
                if mixer { ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer) }
                else { ProcessTapCapture.renderSingle(context: context, input: input.pointer, output: output.pointer) }
            }
            let allocations = recording_allocations_end()
            XCTAssertEqual(allocations, 0)
        }
        #endif
    }

    func testAggregateMembershipAndClockForEverySwitchCombination() {
        for enabled in [false, true] {
            for mic in [false, true] {
                let configuration = RecordingConfiguration(enabled: enabled, includeMic: mic)
                for mixer in [false, true] {
                    let description = mixer
                        ? ProcessTapCapture.makeMixerAggregateDescription(outputDeviceUID: "dac", tapUUIDs: [UUID()],
                            recording: configuration, driverUID: "driver", microphoneUID: "mic")
                        : ProcessTapCapture.makeAggregateDeviceDescription(outputDeviceUID: "dac", tapUUID: UUID(),
                            recording: configuration, driverUID: "driver", microphoneUID: "mic")
                    let devices = description[kAudioAggregateDeviceSubDeviceListKey as String] as! [[String: Any]]
                    XCTAssertEqual(devices.compactMap { $0[kAudioSubDeviceUIDKey as String] as? String },
                        ["dac"] + (enabled ? ["driver"] : []) + (enabled && mic ? ["mic"] : []))
                    XCTAssertEqual(description[kAudioAggregateDeviceClockDeviceKey as String] as? String, "dac")
                    for device in devices.dropFirst() {
                        XCTAssertEqual(device[kAudioSubDeviceDriftCompensationKey as String] as? Bool, true)
                    }
                }
            }
        }
    }

    func testSameDeviceMicDoesNotDuplicateDACInAggregate() {
        let description = ProcessTapCapture.makeAggregateDeviceDescription(outputDeviceUID: "dac", tapUUID: UUID(),
            recording: RecordingConfiguration(enabled: true, includeMic: true), driverUID: "driver", microphoneUID: "dac")
        XCTAssertEqual((description[kAudioAggregateDeviceSubDeviceListKey as String] as? [[String: Any]])?.count, 2)
    }

    func testDriverRoutesReportUnavailable() {
        XCTAssertTrue(RecordingConfiguration.isAvailable(captureMode: .processTap))
        XCTAssertFalse(RecordingConfiguration.isAvailable(captureMode: .halInput))
        XCTAssertFalse(RecordingConfiguration.isAvailable(captureMode: .sharedMemory))
    }

    func testSnapshotRoundTripAndOldDecodeDefaults() throws {
        var snapshot = AppStateSnapshot.default
        snapshot.recordingEnabled = true
        snapshot.recordingIncludeMic = true
        snapshot.recordingMicrophoneUID = "mic"
        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(AppStateSnapshot.self, from: data)
        XCTAssertTrue(restored.recordingEnabled)
        XCTAssertTrue(restored.recordingIncludeMic)
        XCTAssertEqual(restored.recordingMicrophoneUID, "mic")
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["recordingEnabled", "recordingIncludeMic", "recordingMicrophoneUID"] { legacy.removeValue(forKey: key) }
        let old = try JSONDecoder().decode(AppStateSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertFalse(old.recordingEnabled)
        XCTAssertFalse(old.recordingIncludeMic)
        XCTAssertNil(old.recordingMicrophoneUID)
    }
}

private final class RecordingBuffers {
    let pointer: UnsafeMutablePointer<AudioBufferList>
    private let data: [UnsafeMutablePointer<Float>]
    init(channels: [Int], frames: Int, values: [Float]) {
        pointer = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<AudioBufferList>.size + max(0, channels.count - 1) * MemoryLayout<AudioBuffer>.stride,
            alignment: MemoryLayout<AudioBufferList>.alignment).assumingMemoryBound(to: AudioBufferList.self)
        pointer.pointee.mNumberBuffers = UInt32(channels.count)
        data = channels.map { .allocate(capacity: max(1, $0 * frames)) }
        let buffers = UnsafeMutableAudioBufferListPointer(pointer)
        var base = 0
        for index in channels.indices {
            for frame in 0..<frames {
                for channel in 0..<channels[index] { data[index][frame * channels[index] + channel] = values[base + channel] }
            }
            buffers[index] = AudioBuffer(mNumberChannels: UInt32(channels[index]),
                mDataByteSize: UInt32(channels[index] * frames * 4), mData: data[index])
            base += channels[index]
        }
    }
    func sample(_ buffer: Int, _ index: Int) -> Float { data[buffer][index] }
    deinit { for buffer in data { buffer.deallocate() }; pointer.deallocate() }
}

@MainActor
final class MixerRecordingStateTests: XCTestCase {
    func testRecordingCompensationFollowsVolumeEvenWhenHALBoostIsDisabled() {
        let manager = VolumeManager(volumeService: DeviceVolumeService())
        var recordingGain: Float = 0
        var muted = false
        manager.onRecordingStateChanged = { recordingGain = $0; muted = $1 }
        manager.setGain(0.375) // Driver mapping: -40 dB, or 0.01 linear.
        XCTAssertEqual(manager.boostGain(), 100, accuracy: 1e-4)
        XCTAssertEqual(recordingGain, 100, accuracy: 1e-4)
        manager.setBoostEnabled(false)
        XCTAssertEqual(manager.boostGain(), 1)
        XCTAssertEqual(manager.outputVolume(), 0.375) // Disabling boost does not set driver volume to unity.
        XCTAssertEqual(recordingGain, 100, accuracy: 1e-4)
        manager.setGain(1)
        XCTAssertEqual(recordingGain, 1)
        manager.setMuted(true)
        XCTAssertTrue(muted)
        XCTAssertEqual(recordingGain, 1)
        manager.setMuted(false)
        XCTAssertFalse(muted)
        manager.setGain(0)
        XCTAssertEqual(recordingGain, 1) // No reciprocal of zero; the driver itself supplies silence.
    }

    func testEveryRecordingTopologyEditAdvancesRouteGeneration() {
        let store = EqumaczerStore(startAutomation: false)
        store.channelController.stop()
        let coordinator = store.routingCoordinator
        let generation = coordinator.routeGeneration
        coordinator.updateRecordingConfiguration(RecordingConfiguration(enabled: true))
        coordinator.updateRecordingConfiguration(RecordingConfiguration(enabled: true, includeMic: true))
        coordinator.updateRecordingConfiguration(RecordingConfiguration(enabled: true, includeMic: true, microphoneUID: "mic"))
        coordinator.updateRecordingConfiguration(RecordingConfiguration())
        XCTAssertEqual(coordinator.routeGeneration, generation + 4)
        coordinator.updateRecordingConfiguration(RecordingConfiguration())
        XCTAssertEqual(coordinator.routeGeneration, generation + 4)
    }

    func testMicPermissionOnlyRequestedOnExplicitMicEnableAndDenialTurnsItOff() async {
        let permission = RecordingPermission(granted: false)
        let controller = RecordingController(permission: permission)
        controller.updateEnabled(true)
        XCTAssertEqual(permission.requests, 0)
        await controller.updateIncludeMic(true)
        XCTAssertEqual(permission.requests, 1)
        XCTAssertFalse(controller.configuration.includeMic)
        XCTAssertEqual(controller.notice, "Allow equmaczer under Microphone in Privacy & Security.")
    }

    func testGrantedMicPreferenceSurvivesRecordingSwitchOff() async {
        let controller = RecordingController(permission: RecordingPermission(granted: true))
        controller.updateEnabled(true)
        await controller.updateIncludeMic(true)
        controller.updateMicrophone("mic")
        XCTAssertTrue(controller.configuration.includeMic)
        controller.updateEnabled(false)
        XCTAssertTrue(controller.configuration.includeMic) // preference retained while feed is off
        XCTAssertFalse(controller.configuration.enabled)
    }

    func testRestoreNeverPromptsAndDropsUnpermittedMic() {
        let permission = RecordingPermission(granted: false)
        let controller = RecordingController(permission: permission)
        var snapshot = AppStateSnapshot.default
        snapshot.recordingEnabled = true
        snapshot.recordingIncludeMic = true
        controller.restore(snapshot)
        XCTAssertEqual(permission.requests, 0)
        XCTAssertTrue(controller.configuration.enabled)
        XCTAssertFalse(controller.configuration.includeMic)
        XCTAssertNotNil(controller.notice)
    }
}

@MainActor
private final class RecordingPermission: PermissionRequesting {
    let isMicPermissionGranted: Bool
    var requests = 0
    init(granted: Bool) { isMicPermissionGranted = granted }
    func requestMicPermission() async -> Bool { requests += 1; return isMicPermissionGranted }
}
