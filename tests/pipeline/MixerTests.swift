import Atomics
import CoreAudio
import XCTest
@testable import equmaczer

final class MixerTests: XCTestCase {
    private func feed(_ mixer: ChannelMixer, _ channel: AudioChannel, left: Float, right: Float, frames: Int = 64) {
        let l = [Float](repeating: left, count: frames)
        let r = [Float](repeating: right, count: frames)
        l.withUnsafeBufferPointer { lp in
            r.withUnsafeBufferPointer { rp in
                mixer.slot(for: channel).write(left: lp.baseAddress!, right: rp.baseAddress!, frameCount: frames)
            }
        }
    }

    func testStereoSummingDistinctLeftAndRight() {
        let mixer = ChannelMixer(maxFrameCount: 64)
        mixer.setActive([.music, .calls])
        feed(mixer, .music, left: 0.1, right: -0.2)
        feed(mixer, .calls, left: 0.3, right: 0.15)
        mixer.process(frameCount: 64)
        for i in 0..<64 {
            XCTAssertEqual(mixer.output(0)[i], 0.4, accuracy: 1e-6)
            XCTAssertEqual(mixer.output(1)[i], -0.05, accuracy: 1e-6)
        }
    }

    func testProcessedSumIncludesIndependentChannelGains() {
        let mixer = ChannelMixer(maxFrameCount: 64)
        mixer.setActive([.music, .calls])
        mixer.slot(for: .music).gainBits.store(Float(0.5).bitPattern, ordering: .relaxed)
        mixer.slot(for: .calls).gainBits.store(Float(0.25).bitPattern, ordering: .relaxed)
        feed(mixer, .music, left: 0.2, right: 0.4)
        feed(mixer, .calls, left: -0.4, right: 0.8)
        mixer.process(frameCount: 64)
        XCTAssertEqual(mixer.output(0)[32], 0, accuracy: 1e-6)
        XCTAssertEqual(mixer.output(1)[32], 0.4, accuracy: 1e-6)
    }

    func testFailureSilencesOnlyItsChannel() {
        let mixer = ChannelMixer(maxFrameCount: 64)
        mixer.setActive([.music, .calls])
        feed(mixer, .music, left: 1, right: 1)
        feed(mixer, .calls, left: 0.2, right: -0.3)
        mixer.slot(for: .music).failed.store(true, ordering: .releasing)
        mixer.process(frameCount: 64)
        XCTAssertEqual(mixer.failedChannels, [.music])
        for i in 0..<64 {
            XCTAssertEqual(mixer.output(0)[i], 0.2, accuracy: 1e-6)
            XCTAssertEqual(mixer.output(1)[i], -0.3, accuracy: 1e-6)
        }
    }

    func testAllFailedOutputsSilence() {
        let mixer = ChannelMixer(maxFrameCount: 64)
        mixer.setActive([.music])
        feed(mixer, .music, left: 1, right: 1)
        mixer.slot(for: .music).failed.store(true, ordering: .relaxed)
        mixer.process(frameCount: 64)
        XCTAssertEqual(mixer.output(0)[0], 0)
        XCTAssertEqual(mixer.output(1)[0], 0)
    }

    func testInactiveSlotIsNotSummed() {
        let mixer = ChannelMixer(maxFrameCount: 64)
        mixer.setActive([.calls])
        feed(mixer, .music, left: 1, right: 1)
        mixer.process(frameCount: 64)
        XCTAssertEqual(mixer.output(0)[0], 0)
    }

    func testUnderflowZeroFillsBothEars() {
        let mixer = ChannelMixer(maxFrameCount: 64)
        mixer.setActive([.music])
        feed(mixer, .music, left: 0.4, right: -0.2, frames: 10)
        mixer.process(frameCount: 64)
        for i in 10..<64 {
            XCTAssertEqual(mixer.output(0)[i], 0)
            XCTAssertEqual(mixer.output(1)[i], 0)
        }
    }

    func testBypassSkipsLocalTreatmentGain() {
        let mixer = ChannelMixer(maxFrameCount: 64)
        mixer.setActive([.music])
        mixer.slot(for: .music).gainBits.store(Float(0.1).bitPattern, ordering: .relaxed)
        feed(mixer, .music, left: 0.4, right: -0.2)
        mixer.process(frameCount: 64, treated: false)
        XCTAssertEqual(mixer.output(0)[0], 0.4)
        XCTAssertEqual(mixer.output(1)[0], -0.2)
    }

    /// Portable allocation regression method: borrowed output identities on
    /// every call, including silence. Source audit also checks the render call
    /// graph for allocating operations. Identity does not count transient mallocs.
    func testNoAllocationOutputStorageReusedForTenThousandCalls() {
        let mixer = ChannelMixer(maxFrameCount: 64)
        let left = mixer.output(0)
        let right = mixer.output(1)
        let slotLeft = mixer.slot(for: .music).left
        let slotRight = mixer.slot(for: .music).right
        let coefficient = SVFCoefficients(biquad: BiquadMath.calculateCoefficients(
            type: .lowShelf, sampleRate: 48000, frequency: 500, q: 0.7, gain: -6))
        for chain in [mixer.slot(for: .music).leftEQ, mixer.slot(for: .music).rightEQ] {
            chain.stageFullUpdate(coefficients: [coefficient], bypassFlags: [false], activeBandCount: 1, layerBypass: false)
        }
        let signal = [Float](repeating: 0.1, count: 64)
        signal.withUnsafeBufferPointer { signal in
            for i in 0..<10_000 {
                mixer.setActive(i % 2 == 0 ? [.music] : [])
                mixer.slot(for: .music).write(left: signal.baseAddress!, right: signal.baseAddress!, frameCount: 64)
                mixer.process(frameCount: 64)
                XCTAssertEqual(mixer.output(0), left)
                XCTAssertEqual(mixer.output(1), right)
                XCTAssertEqual(mixer.slot(for: .music).left, slotLeft)
                XCTAssertEqual(mixer.slot(for: .music).right, slotRight)
            }
        }
    }

    func testDriftFasterAndSlowerTapsStayBoundedOverLongRun() {
        let mixer = ChannelMixer(maxFrameCount: 512)
        mixer.setActive([.music, .calls])
        let signal = [Float](repeating: 0.1, count: 512)
        signal.withUnsafeBufferPointer { signal in
            for _ in 0..<20_000 {
                mixer.slot(for: .music).write(left: signal.baseAddress!, right: signal.baseAddress!, frameCount: 512)
                mixer.slot(for: .calls).write(left: signal.baseAddress!, right: signal.baseAddress!, frameCount: 510)
                mixer.process(frameCount: 511)
                for slot in mixer.slots {
                    XCTAssertLessThanOrEqual(slot.ringBuffer.availableToRead() / 2, ChannelMixer.maximumQueuedFrames)
                    XCTAssertEqual(slot.ringBuffer.getOverflowCount(), 0)
                }
            }
        }
        XCTAssertGreaterThan(mixer.slot(for: .calls).ringBuffer.getUnderrunCount(), 0)
        XCTAssertTrue(mixer.output(0)[0].isFinite)
    }

    func testLatencyBudgetAtMaximumCallbackAndRecoveryBacklog() {
        let mixer = ChannelMixer()
        mixer.setActive([.music])
        let count = Int(mixer.maxFrameCount)
        feed(mixer, .music, left: 0.1, right: 0.2, frames: count)
        feed(mixer, .music, left: 0.1, right: 0.2, frames: count)
        mixer.process(frameCount: mixer.maxFrameCount)
        let queued = mixer.slot(for: .music).ringBuffer.availableToRead() / 2
        XCTAssertEqual(queued, ChannelMixer.maximumQueuedFrames)
        for rate in [44100.0, 48000, 96000, 192000] {
            let softwareLatencyMS = Double(count + queued + 12) / rate * 1000
            XCTAssertLessThanOrEqual(softwareLatencyMS, ChannelMixer.statedLatencyBudgetMS)
        }
    }

    func testFrameCountClampedToPreallocatedStorage() {
        let mixer = ChannelMixer(maxFrameCount: 64)
        mixer.setActive([.music])
        feed(mixer, .music, left: 0.1, right: 0.2)
        mixer.process(frameCount: 128)
        XCTAssertEqual(mixer.output(1)[63], 0.2)
    }

    func testZeroFrameCountIsSafe() {
        let mixer = ChannelMixer(maxFrameCount: 64)
        mixer.process(frameCount: 0)
        XCTAssertEqual(mixer.output(0)[0], 0)
    }

    func testChannelTapIncludesOnlyItsOwnProcesses() {
        let uuid = UUID()
        let tap = ProcessTapCapture.makeChannelTapDescription(tapUUID: uuid,
            processObjectIDs: [11, 22], name: "Music")
        XCTAssertEqual(tap.processes, [11, 22])
        XCTAssertFalse(tap.isExclusive)
        XCTAssertTrue(tap.isMixdown)
        XCTAssertTrue(tap.isPrivate)
        XCTAssertEqual(tap.uuid, uuid)
        XCTAssertEqual(tap.muteBehavior, .mutedWhenTapped)
        let calls = ProcessTapCapture.makeChannelTapDescription(tapUUID: UUID(), processObjectIDs: [33], name: "Calls")
        XCTAssertEqual(calls.processes, [33])
        XCTAssertFalse(calls.isExclusive)
    }

    func testGlobalTapStillExcludesProcesses() {
        let tap = ProcessTapCapture.makeGlobalStereoTapDescription(excludedProcessObjectIDs: [9])
        XCTAssertTrue(tap.isExclusive)
        XCTAssertEqual(tap.processes, [9])
    }

    func testAggregateUsesDACClockAndResamplesEachTap() {
        let ids = [UUID(), UUID()]
        let description = ProcessTapCapture.makeMixerAggregateDescription(outputDeviceUID: "dac", tapUUIDs: ids)
        XCTAssertEqual(description[kAudioAggregateDeviceClockDeviceKey] as? String, "dac")
        let taps = description[kAudioAggregateDeviceTapListKey] as! [[String: Any]]
        XCTAssertEqual(taps.count, 2)
        for i in ids.indices {
            XCTAssertEqual(taps[i][kAudioSubTapUIDKey] as? String, ids[i].uuidString)
            XCTAssertEqual(taps[i][kAudioSubTapDriftCompensationKey] as? Bool, true)
        }
    }

    func testIndependentEQChainsProduceTheirProcessedStereoSum() {
        let mixer = ChannelMixer(maxFrameCount: 64)
        mixer.setActive([.music, .calls])
        let musicCoefficient = SVFCoefficients(biquad: BiquadMath.calculateCoefficients(
            type: .lowShelf, sampleRate: 48000, frequency: 500, q: 0.7, gain: -6))
        let callsCoefficient = SVFCoefficients(biquad: BiquadMath.calculateCoefficients(
            type: .highShelf, sampleRate: 48000, frequency: 2500, q: 0.7, gain: 4))
        let referenceLeft = EQChain(maxFrameCount: 64)
        let referenceRight = EQChain(maxFrameCount: 64)
        for (channel, coefficient, reference) in [
            (AudioChannel.music, musicCoefficient, referenceLeft),
            (.calls, callsCoefficient, referenceRight)
        ] {
            for chain in [mixer.slot(for: channel).leftEQ, mixer.slot(for: channel).rightEQ, reference] {
                chain.stageFullUpdate(coefficients: [coefficient], bypassFlags: [false], activeBandCount: 1, layerBypass: false)
            }
        }
        let l = UnsafeMutablePointer<Float>.allocate(capacity: 64)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: 64)
        defer { l.deallocate(); r.deallocate() }
        for block in 0..<12 {
            l.update(repeating: 0.1, count: 64)
            r.update(repeating: -0.2, count: 64)
            mixer.slot(for: .music).write(left: l, right: r, frameCount: 64)
            // Calls uses the same L/R ratio so references remain independent.
            mixer.slot(for: .calls).write(left: l, right: r, frameCount: 64)
            referenceLeft.applyPendingUpdates()
            referenceRight.applyPendingUpdates()
            referenceLeft.process(buffer: l, frameCount: 64)
            // Use calls reference on 0.1 too, then scale for the R check.
            r.update(repeating: 0.1, count: 64)
            referenceRight.process(buffer: r, frameCount: 64)
            mixer.process(frameCount: 64)
            for frame in 0..<64 {
                XCTAssertEqual(mixer.output(0)[frame], l[frame] + r[frame], accuracy: 1e-6, "block \(block)")
                XCTAssertEqual(mixer.output(1)[frame], -2 * (l[frame] + r[frame]), accuracy: 1e-6)
            }
        }
    }

    func testConcurrentMaskAndHealthPublicationWithRendering() async {
        let mixer = ChannelMixer(maxFrameCount: 64)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for i in 0..<10_000 {
                    mixer.setActive(i % 2 == 0 ? [.music, .calls] : [.calls])
                    mixer.slot(for: .music).failed.store(i % 3 == 0, ordering: .releasing)
                }
            }
            group.addTask {
                for _ in 0..<10_000 { mixer.process(frameCount: 64) }
            }
        }
        XCTAssertTrue(mixer.output(0)[0].isFinite)
    }
}

@MainActor
final class MixerRouteTests: XCTestCase {
    func testIdleAppProcessAppearingChangesPlanAndRouteGeneration() {
        let store = EqumaczerStore(startAutomation: false)
        store.channelController.stop()
        let coordinator = store.routingCoordinator
        let channels: [String: AudioChannel] = ["app": .music]
        let volumes: [String: Float] = ["app": 0.4]
        coordinator.updateChannelTapAssignments(AppTapPlan.assignments(processes: ["app": []],
            channels: channels, volumes: volumes, excluded: []))
        XCTAssertTrue(coordinator.channelTapAssignments.isEmpty)
        let generation = coordinator.routeGeneration
        coordinator.updateChannelTapAssignments(AppTapPlan.assignments(processes: ["app": [11]],
            channels: channels, volumes: volumes, excluded: []))
        XCTAssertEqual(coordinator.channelTapAssignments, [
            ChannelTapAssignment(channel: .music, objectIDs: [11], bundleID: "app")])
        XCTAssertEqual(coordinator.routeGeneration, generation + 1)
    }

    func testTwoHundredTapSetChangesUseCoordinatorRouteSeam() {
        let store = EqumaczerStore()
        store.channelController.stop()
        let coordinator = store.routingCoordinator
        let initial = coordinator.routeGeneration
        for i in 0..<200 {
            coordinator.updateChannelTapAssignments(i % 2 == 0
                ? [ChannelTapAssignment(channel: .music, objectIDs: [UInt32(i + 100)])] : [])
        }
        XCTAssertEqual(coordinator.channelTapAssignments, [])
        XCTAssertEqual(coordinator.routeGeneration, initial + 200)
        coordinator.updateChannelTapAssignments([])
        XCTAssertEqual(coordinator.routeGeneration, initial + 200)
    }

    func testDuplicateChannelAssignmentsMergeIntoOneTap() {
        let store = EqumaczerStore()
        store.channelController.stop()
        let coordinator = store.routingCoordinator
        coordinator.updateChannelTapAssignments([
            ChannelTapAssignment(channel: .music, objectIDs: [2, 1]),
            ChannelTapAssignment(channel: .music, objectIDs: [2, 3])])
        XCTAssertEqual(coordinator.channelTapAssignments, [ChannelTapAssignment(channel: .music, objectIDs: [1, 2, 3])])
        let generation = coordinator.routeGeneration
        coordinator.updateChannelTapAssignments([ChannelTapAssignment(channel: .music, objectIDs: [3, 2, 1])])
        XCTAssertEqual(coordinator.routeGeneration, generation)
    }

    func testTapSetCanonicalOrderDoesNotCauseFalseRouteEvent() {
        let store = EqumaczerStore()
        store.channelController.stop()
        let coordinator = store.routingCoordinator
        coordinator.updateChannelTapAssignments([ChannelTapAssignment(channel: .music, objectIDs: [2, 1])])
        let generation = coordinator.routeGeneration
        coordinator.updateChannelTapAssignments([ChannelTapAssignment(channel: .music, objectIDs: [1, 2, 1])])
        XCTAssertEqual(coordinator.routeGeneration, generation)
    }
}

/// A real AudioBufferList with controllable planar/interleaved stream layout.
private final class MixerBufferList {
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
        for i in channels.indices {
            for frame in 0..<frames {
                for channel in 0..<channels[i] { data[i][frame * channels[i] + channel] = values[base + channel] }
            }
            buffers[i] = AudioBuffer(mNumberChannels: UInt32(channels[i]),
                mDataByteSize: UInt32(channels[i] * frames * 4), mData: data[i])
            base += channels[i]
        }
    }

    func sample(buffer: Int, index: Int) -> Float { data[buffer][index] }
    deinit { for buffer in data { buffer.deallocate() }; pointer.deallocate() }
}

final class MixerCallbackTests: XCTestCase {
    private func context() -> RenderCallbackContext {
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
        let mixer = ChannelMixer(maxFrameCount: 64)
        mixer.setActive([.music, .calls])
        context.mixer = mixer
        context.mixerTapSlots = [mixer.slot(for: .music), mixer.slot(for: .calls)]
        context.useTapInputBuffers()
        context.processingMode = 0
        return context
    }

    func testInterleavedTapsReachInterleavedHardwareOutput() {
        let context = context()
        let input = MixerBufferList(channels: [2, 2], frames: 64, values: [0.1, -0.2, 0.3, 0.1])
        let output = MixerBufferList(channels: [2], frames: 64, values: [9, 9])
        ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer)
        for frame in 0..<64 {
            XCTAssertEqual(output.sample(buffer: 0, index: frame * 2), 0.4, accuracy: 1e-6)
            XCTAssertEqual(output.sample(buffer: 0, index: frame * 2 + 1), -0.1, accuracy: 1e-6)
        }
        XCTAssertEqual(context.inputFramesReceived, 64)
    }

    // The tap deafness check reads the input meters; the mixer path must feed them.
    func testMixerPathFeedsInputMeters() {
        let context = context()
        context.setMetersEnabled(true)
        let input = MixerBufferList(channels: [2, 2], frames: 64, values: [0.1, -0.2, 0.3, 0.1])
        let output = MixerBufferList(channels: [2], frames: 64, values: [0, 0])
        ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer)
        XCTAssertGreaterThan(context.rmsSnapshot().input.max() ?? -90, TapDeafness.silenceFloorDB)
    }

    // Hidden window turns meters off; the deafness proof's probe must still measure.
    func testMeterProbeMeasuresWithMetersOff() {
        let context = context()
        context.setMetersEnabled(false)
        context.setMeterProbe(true)
        let input = MixerBufferList(channels: [2, 2], frames: 64, values: [0.1, -0.2, 0.3, 0.1])
        let output = MixerBufferList(channels: [2], frames: 64, values: [0, 0])
        ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer)
        XCTAssertGreaterThan(context.rmsSnapshot().input.max() ?? -90, TapDeafness.silenceFloorDB)
    }

    func testPlanarTapsAndPhysicalMicrophoneOffset() {
        let context = context()
        context.mixerInputChannelOffset = 1
        let input = MixerBufferList(channels: [1, 1, 1, 1, 1], frames: 64, values: [99, 0.1, -0.2, 0.3, 0.1])
        let output = MixerBufferList(channels: [1, 1, 1], frames: 64, values: [9, 9, 9])
        ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer)
        XCTAssertEqual(output.sample(buffer: 0, index: 63), 0.4, accuracy: 1e-6)
        XCTAssertEqual(output.sample(buffer: 1, index: 63), -0.1, accuracy: 1e-6)
        XCTAssertEqual(output.sample(buffer: 2, index: 63), 0)
    }

    func testMissingInputClearsOutputAndDoesNotAdvanceLiveness() {
        let context = context()
        let input = MixerBufferList(channels: [], frames: 64, values: [])
        let output = MixerBufferList(channels: [2], frames: 64, values: [9, 9])
        ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer)
        XCTAssertEqual(output.sample(buffer: 0, index: 0), 0)
        XCTAssertEqual(output.sample(buffer: 0, index: 127), 0)
        XCTAssertEqual(context.inputFramesReceived, 0)
    }

    func testStoppingSilencesOutput() {
        let context = context()
        context.setIsStopping(true)
        let input = MixerBufferList(channels: [2, 2], frames: 64, values: [1, 1, 1, 1])
        let output = MixerBufferList(channels: [2], frames: 64, values: [9, 9])
        ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer)
        XCTAssertEqual(output.sample(buffer: 0, index: 127), 0)
        XCTAssertEqual(context.inputFramesReceived, 0)
    }

    func testShortInputDoesNotReadPastBufferOrRepeatOldSamples() {
        let context = context()
        let input = MixerBufferList(channels: [2, 2], frames: 10, values: [0.1, 0.2, 0.3, 0.4])
        let output = MixerBufferList(channels: [2], frames: 64, values: [9, 9])
        ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer)
        XCTAssertEqual(output.sample(buffer: 0, index: 0), 0.4, accuracy: 1e-6)
        XCTAssertEqual(output.sample(buffer: 0, index: 20), 0)
        XCTAssertEqual(output.sample(buffer: 0, index: 127), 0)
        XCTAssertEqual(context.inputFramesReceived, 10)
    }

    func testTapEarsWithDifferentStreamStrides() {
        let context = context()
        let input = MixerBufferList(channels: [1, 2, 1], frames: 64, values: [0.1, -0.2, 0.3, 0.1])
        let output = MixerBufferList(channels: [2], frames: 64, values: [9, 9])
        ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer)
        XCTAssertEqual(output.sample(buffer: 0, index: 126), 0.4, accuracy: 1e-6)
        XCTAssertEqual(output.sample(buffer: 0, index: 127), -0.1, accuracy: 1e-6)
    }

    func testMasterOutputGainScalesBothInterleavedEars() {
        let context = context()
        context.processingMode = 1
        context.outputGainLinear = 0.5
        context.setTargetOutputGain(0.5)
        let input = MixerBufferList(channels: [2, 2], frames: 64, values: [0.1, 0.2, 0.1, 0.2])
        let output = MixerBufferList(channels: [2], frames: 64, values: [9, 9])
        ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer)
        for frame in 0..<64 {
            // The master true-peak limiter delays audio by 12 frames.
            XCTAssertEqual(output.sample(buffer: 0, index: frame * 2), frame < 12 ? 0 : 0.1, accuracy: 1e-5)
            XCTAssertEqual(output.sample(buffer: 0, index: frame * 2 + 1), frame < 12 ? 0 : 0.2, accuracy: 1e-5)
        }
    }
}

/// Deterministic control-side hardware boundary; the capture/mixer/context are real.
private final class MixerHardware: ProcessTapHardwareControlling {
    var failingProcesses: Set<AudioObjectID> = []
    var deviceUIDs: [AudioDeviceID: String] = [1: "test-dac"]
    var inputChannels: [AudioDeviceID: Int] = [:]
    var outputChannels: [AudioDeviceID: Int] = [1: 2]
    var defaultMic: AudioDeviceID?
    var defaultInputQueries = 0
    var aggregateDescriptions: [[String: Any]] = []
    var aggregateStatus: OSStatus = noErr
    var registrationStatus: OSStatus = noErr
    var startStatus: OSStatus = noErr
    var descriptions: [CATapDescription] = []
    var liveTaps: Set<AudioObjectID> = []
    var events: [String] = []
    var callback: AudioDeviceIOProc?
    var contextPointer: UnsafeMutableRawPointer?

    func configureStreams(_ device: AudioDeviceID, _ id: AudioDeviceIOProcID, context: RenderCallbackContext) -> OSStatus { noErr }
    func outputChannelCount(_ device: AudioDeviceID) -> Int { outputChannels[device] ?? 0 }
    func deviceUID(_ device: AudioDeviceID) -> String? { deviceUIDs[device] }
    func inputChannelCount(_ device: AudioDeviceID) -> Int { inputChannels[device] ?? 0 }
    func deviceID(forUID uid: String) -> AudioDeviceID? { deviceUIDs.first { $0.value == uid }?.key }
    func defaultInputDeviceID() -> AudioDeviceID? { defaultInputQueries += 1; return defaultMic }
    func currentProcessObjectID() -> AudioObjectID? { 99 }
    func isAnyProcessRunningOutput(processObjectIDs: [AudioObjectID]?) -> Bool { false }
    func createTap(_ description: CATapDescription, _ id: inout AudioObjectID) -> OSStatus {
        descriptions.append(description)
        if !description.isExclusive && description.processes.contains(where: { failingProcesses.contains($0) }) {
            return -1
        }
        id = UInt32(descriptions.count + 100)
        liveTaps.insert(id)
        return noErr
    }
    func destroyTap(_ id: AudioObjectID) { liveTaps.remove(id); events.append("tap") }
    func createAggregate(_ description: CFDictionary, _ id: inout AudioObjectID) -> OSStatus {
        aggregateDescriptions.append(description as! [String: Any])
        if aggregateStatus == noErr { id = 500 }
        return aggregateStatus
    }
    func destroyAggregate(_ id: AudioObjectID) { events.append("aggregate") }
    func createIOProc(_ device: AudioDeviceID, _ callback: AudioDeviceIOProc,
                      _ context: UnsafeMutableRawPointer, _ id: inout AudioDeviceIOProcID?) -> OSStatus {
        self.callback = callback
        contextPointer = context
        if registrationStatus == noErr { id = callback }
        return registrationStatus
    }
    func destroyIOProc(_ device: AudioDeviceID, _ id: AudioDeviceIOProcID) { events.append("proc") }
    func start(_ device: AudioDeviceID, _ id: AudioDeviceIOProcID) -> OSStatus { startStatus }
    func stop(_ device: AudioDeviceID, _ id: AudioDeviceIOProcID) { events.append("stop") }
}

final class MixerLifecycleTests: XCTestCase {
    private let assignments = [ChannelTapAssignment(channel: .music, objectIDs: [11]),
                               ChannelTapAssignment(channel: .calls, objectIDs: [22])]

    private func start(_ capture: ProcessTapCapture, _ context: RenderCallbackContext,
                       assignments: [ChannelTapAssignment]) throws {
        try capture.startMixer(outputDeviceID: 1, context: context,
                               mixer: ChannelMixer(maxFrameCount: 64), assignments: assignments).get()
    }

    func testLivenessScopeIncludesOnlySuccessfulTapsAndExcludesOwnProcess() throws {
        let hardware = MixerHardware()
        hardware.failingProcesses = [11]
        let capture = ProcessTapCapture(hardware: hardware)
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
        try start(capture, context, assignments: [
            ChannelTapAssignment(channel: .music, objectIDs: [11]),
            ChannelTapAssignment(channel: .calls, objectIDs: [22, 99])
        ])
        XCTAssertEqual(capture.tappedProcessObjectIDs, [22])
        capture.stop()
        XCTAssertNil(capture.tappedProcessObjectIDs)
    }

    func testGlobalFallbackLivenessChecksAllProcesses() throws {
        let hardware = MixerHardware()
        hardware.failingProcesses = [11, 22]
        let capture = ProcessTapCapture(hardware: hardware)
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
        try start(capture, context, assignments: assignments)
        XCTAssertFalse(capture.usesMixer)
        XCTAssertNil(capture.tappedProcessObjectIDs)
        capture.stop()
    }

    func testCreationFailureLeavesHealthyTapPlayingAndReleasesResourcesInOrder() throws {
        let hardware = MixerHardware()
        hardware.failingProcesses = [11]
        let capture = ProcessTapCapture(hardware: hardware)
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
        context.processingMode = 0
        try start(capture, context, assignments: assignments)
        XCTAssertTrue(capture.usesMixer)
        XCTAssertEqual(capture.failedChannels, [.music])
        XCTAssertEqual(context.mixerTapSlots.map(\.channel), [.calls])
        let input = MixerBufferList(channels: [2], frames: 64, values: [0.2, -0.3])
        let output = MixerBufferList(channels: [2], frames: 64, values: [9, 9])
        ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer)
        XCTAssertEqual(output.sample(buffer: 0, index: 0), 0.2, accuracy: 1e-6)
        XCTAssertEqual(output.sample(buffer: 0, index: 127), -0.3, accuracy: 1e-6)
        capture.stop()
        XCTAssertTrue(hardware.liveTaps.isEmpty)
        XCTAssertEqual(hardware.events, ["stop", "proc", "aggregate", "tap"])
        capture.stop()
        XCTAssertEqual(hardware.events.count, 4)
    }

    func testAllTapFailuresUseGlobalStageFallback() throws {
        let hardware = MixerHardware()
        hardware.failingProcesses = [11, 22]
        let capture = ProcessTapCapture(hardware: hardware)
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
        context.processingMode = 0
        try start(capture, context, assignments: assignments)
        XCTAssertFalse(capture.usesMixer)
        XCTAssertEqual(capture.failedChannels, [.music, .calls])
        XCTAssertTrue(hardware.descriptions.last!.isExclusive)
        // Exercise the actual fallback IOProc: its processing pointers must
        // reference tap input, rather than the HAL ring's unused output buffers.
        let input = MixerBufferList(channels: [2], frames: 64, values: [0.2, -0.3])
        let output = MixerBufferList(channels: [2], frames: 64, values: [9, 9])
        var timestamp = AudioTimeStamp()
        withUnsafePointer(to: &timestamp) { time in
            _ = hardware.callback!(500, time, input.pointer, time, output.pointer, time, hardware.contextPointer)
        }
        XCTAssertEqual(output.sample(buffer: 0, index: 0), 0.2, accuracy: 1e-6)
        XCTAssertEqual(output.sample(buffer: 0, index: 127), -0.3, accuracy: 1e-6)
        capture.stop()
        XCTAssertTrue(hardware.liveTaps.isEmpty)
    }

    func testEmptyAssignmentsPreserveGlobalStagePath() throws {
        let hardware = MixerHardware()
        let capture = ProcessTapCapture(hardware: hardware)
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
        try start(capture, context, assignments: [])
        XCTAssertFalse(capture.usesMixer)
        XCTAssertEqual(hardware.descriptions.count, 1)
        XCTAssertTrue(hardware.descriptions[0].isExclusive)
        capture.stop()
        XCTAssertTrue(hardware.liveTaps.isEmpty)
    }

    func testAllEmptyProcessListsUseOnlyGlobalTap() throws {
        let hardware = MixerHardware()
        let capture = ProcessTapCapture(hardware: hardware)
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
        try start(capture, context, assignments: [
            ChannelTapAssignment(channel: .music, objectIDs: []),
            ChannelTapAssignment(channel: .calls, objectIDs: [], bundleID: "idle")])
        XCTAssertFalse(capture.usesMixer)
        XCTAssertTrue(capture.failedChannels.isEmpty)
        XCTAssertNil(context.mixer)
        XCTAssertTrue(context.mixerTapSlots.isEmpty)
        XCTAssertEqual(hardware.descriptions.count, 1)
        XCTAssertTrue(hardware.descriptions[0].isExclusive)
        let taps = hardware.aggregateDescriptions[0][kAudioAggregateDeviceTapListKey as String] as! [[String: Any]]
        XCTAssertEqual(taps.count, 1)
        XCTAssertEqual(taps[0][kAudioSubTapUIDKey] as? String, capture.tapUUID.uuidString)
        capture.stop()
        XCTAssertTrue(hardware.liveTaps.isEmpty)
    }

    func testOwnProcessOnlyAssignmentsUseGlobalTap() throws {
        let hardware = MixerHardware()
        let capture = ProcessTapCapture(hardware: hardware)
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
        try start(capture, context, assignments: [
            ChannelTapAssignment(channel: .music, objectIDs: [99], bundleID: "self")])
        XCTAssertFalse(capture.usesMixer)
        XCTAssertTrue(capture.failedChannels.isEmpty)
        XCTAssertEqual(hardware.descriptions.count, 1)
        XCTAssertTrue(hardware.descriptions[0].isExclusive)
        capture.stop()
    }

    func testIdleAppsDoNotCountTowardsSlotLimitOrFailTheirChannel() throws {
        let hardware = MixerHardware()
        let capture = ProcessTapCapture(hardware: hardware)
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
        let idleApps = (0...ChannelMixer.maximumAppSlots).map {
            ChannelTapAssignment(channel: .music, objectIDs: [], bundleID: "idle\($0)")
        }
        try start(capture, context, assignments: idleApps + [
            ChannelTapAssignment(channel: .calls, objectIDs: [22, 99])])
        XCTAssertTrue(capture.usesMixer)
        XCTAssertTrue(capture.failedChannels.isEmpty)
        XCTAssertTrue(context.mixer!.failedChannels.isEmpty)
        XCTAssertEqual(context.mixerTapSlots.map(\.channel), [.calls])
        XCTAssertEqual(hardware.descriptions.count, 1)
        XCTAssertEqual(hardware.descriptions[0].processes, [22])
        XCTAssertFalse(hardware.descriptions[0].isExclusive)
        let taps = hardware.aggregateDescriptions[0][kAudioAggregateDeviceTapListKey as String] as! [[String: Any]]
        XCTAssertEqual(taps.count, 1)
        XCTAssertEqual(taps[0][kAudioSubTapUIDKey] as? String, hardware.descriptions[0].uuid.uuidString)
        capture.stop()
    }

    func testEmptyAppAssignmentIsIdleWhileHealthyChannelRenders() throws {
        let hardware = MixerHardware()
        let capture = ProcessTapCapture(hardware: hardware)
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
        context.processingMode = 0
        let assignments = [ChannelTapAssignment(channel: .music, objectIDs: [], bundleID: "idle"),
                           ChannelTapAssignment(channel: .calls, objectIDs: [22])]
        let mixer = ChannelMixer(maxFrameCount: 64, appAssignments: assignments)
        try capture.startMixer(outputDeviceID: 1, context: context, mixer: mixer, assignments: assignments).get()
        XCTAssertEqual(hardware.descriptions.count, 1)
        XCTAssertEqual(hardware.descriptions[0].processes, [22])
        let taps = hardware.aggregateDescriptions[0][kAudioAggregateDeviceTapListKey as String] as! [[String: Any]]
        XCTAssertEqual(taps.count, 1)
        XCTAssertEqual(taps[0][kAudioSubTapUIDKey] as? String, hardware.descriptions[0].uuid.uuidString)
        XCTAssertTrue(capture.failedChannels.isEmpty)
        XCTAssertTrue(mixer.failedChannels.isEmpty)
        XCTAssertFalse(mixer.appSlot(for: "idle")!.failed.load(ordering: .relaxed))
        XCTAssertEqual(context.mixerTapSlots.map(\.channel), [.calls])
        let input = MixerBufferList(channels: [2], frames: 64, values: [0.2, -0.3])
        let output = MixerBufferList(channels: [2], frames: 64, values: [9, 9])
        ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer)
        XCTAssertEqual(output.sample(buffer: 0, index: 126), 0.2)
        XCTAssertEqual(output.sample(buffer: 0, index: 127), -0.3)
        capture.stop()
    }

    func testIdleAppDoesNotPreventChannelFailureGlobalFallback() throws {
        let hardware = MixerHardware()
        hardware.failingProcesses = [22]
        let capture = ProcessTapCapture(hardware: hardware)
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
        try start(capture, context, assignments: [
            ChannelTapAssignment(channel: .music, objectIDs: [], bundleID: "idle"),
            ChannelTapAssignment(channel: .calls, objectIDs: [22])])
        XCTAssertFalse(capture.usesMixer)
        XCTAssertEqual(capture.failedChannels, [.calls])
        XCTAssertEqual(hardware.descriptions.count, 2)
        XCTAssertEqual(hardware.descriptions[0].processes, [22])
        XCTAssertTrue(hardware.descriptions[1].isExclusive)
        capture.stop()
        XCTAssertTrue(hardware.liveTaps.isEmpty)
    }

    func testStartupFailuresDestroyEveryCreatedTap() {
        for phase in 0..<3 {
            let hardware = MixerHardware()
            if phase == 0 { hardware.aggregateStatus = -1 }
            if phase == 1 { hardware.registrationStatus = -1 }
            if phase == 2 { hardware.startStatus = -1 }
            let capture = ProcessTapCapture(hardware: hardware)
            let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
            XCTAssertThrowsError(try start(capture, context, assignments: assignments))
            XCTAssertTrue(hardware.liveTaps.isEmpty, "phase \(phase)")
            XCTAssertFalse(capture.usesMixer)
            XCTAssertEqual(hardware.events.filter { $0 == "tap" }.count, 2)
        }
    }
}

final class AppTapLifecycleTests: XCTestCase {
    func testAppTapAppearsAndDisappearsWithHealthyChannelStillRendering() throws {
        let hardware = MixerHardware()
        let capture = ProcessTapCapture(hardware: hardware)
        let channel = ChannelTapAssignment(channel: .calls, objectIDs: [22])
        let app = ChannelTapAssignment(channel: .music, objectIDs: [11], bundleID: "a")
        for index in 0..<20 {
            let assignments = index % 2 == 0 ? [channel, app] : [channel]
            let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
            context.processingMode = 0
            let mixer = ChannelMixer(maxFrameCount: 64, appAssignments: assignments)
            try capture.startMixer(outputDeviceID: 1, context: context, mixer: mixer, assignments: assignments).get()
            XCTAssertEqual(hardware.liveTaps.count, assignments.count)
            XCTAssertEqual(mixer.appSlot(for: "a") == nil, index % 2 != 0)
            if let slot = mixer.appSlot(for: "a") { slot.volumeBits.store(Float(0.4).bitPattern, ordering: .relaxed) }
            let input = MixerBufferList(channels: assignments.map { _ in 2 }, frames: 64,
                values: assignments.count == 2 ? [0.2, -0.1, 0.5, -0.5] : [0.2, -0.1])
            let output = MixerBufferList(channels: [2], frames: 64, values: [9, 9])
            for _ in 0..<4 { ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer) }
            XCTAssertEqual(output.sample(buffer: 0, index: 126), assignments.count == 2 ? 0.4 : 0.2, accuracy: 1e-6)
            XCTAssertEqual(output.sample(buffer: 0, index: 127), assignments.count == 2 ? -0.3 : -0.1, accuracy: 1e-6)
            capture.stop()
            XCTAssertTrue(hardware.liveTaps.isEmpty)
        }
        for description in hardware.descriptions {
            XCTAssertFalse(description.isExclusive)
            XCTAssertEqual(description.muteBehavior, .mutedWhenTapped)
        }
    }

    func testFailedAppTapLeavesHealthyChannelAndNeverFallsBackToWrongGain() throws {
        let app = ChannelTapAssignment(channel: .music, objectIDs: [11], bundleID: "a")
        let hardware = MixerHardware()
        hardware.failingProcesses = [11]
        let capture = ProcessTapCapture(hardware: hardware)
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
        context.processingMode = 0
        let assignments = [app, ChannelTapAssignment(channel: .calls, objectIDs: [22])]
        let mixer = ChannelMixer(maxFrameCount: 64, appAssignments: assignments)
        try capture.startMixer(outputDeviceID: 1, context: context, mixer: mixer, assignments: assignments).get()
        XCTAssertTrue(mixer.appSlot(for: "a")!.failed.load(ordering: .relaxed))
        let input = MixerBufferList(channels: [2], frames: 64, values: [0.2, -0.1])
        let output = MixerBufferList(channels: [2], frames: 64, values: [9, 9])
        ProcessTapCapture.renderMixer(context: context, input: input.pointer, output: output.pointer)
        XCTAssertEqual(output.sample(buffer: 0, index: 126), 0.2)
        capture.stop()
        let appOnlyMixer = ChannelMixer(maxFrameCount: 64, appAssignments: [app])
        XCTAssertThrowsError(try capture.startMixer(outputDeviceID: 1, context: context,
            mixer: appOnlyMixer, assignments: [app]).get())
        XCTAssertTrue(hardware.liveTaps.isEmpty)
        XCTAssertTrue(hardware.descriptions.allSatisfy { !$0.isExclusive })
    }
}

final class MixerRecordingLifecycleTests: XCTestCase {
    private func hardware() -> MixerHardware {
        let hardware = MixerHardware()
        hardware.deviceUIDs = [1: "test-dac", 2: DRIVER_DEVICE_UID, 3: "mic"]
        hardware.inputChannels = [1: 1, 2: 2, 3: 1]
        hardware.outputChannels = [1: 4, 2: 2, 3: 2]
        hardware.defaultMic = 3
        return hardware
    }

    func testDefaultMicTopologySkipsDriverInputAndKeepsOneIOProc() throws {
        for mixer in [false, true] {
            let hardware = hardware()
            let capture = ProcessTapCapture(hardware: hardware)
            let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
            context.recordingConfiguration = RecordingConfiguration(enabled: true, includeMic: true)
            if mixer {
                try capture.startMixer(outputDeviceID: 1, context: context, mixer: ChannelMixer(maxFrameCount: 64),
                    assignments: [ChannelTapAssignment(channel: .music, objectIDs: [11, 99])]).get()
                XCTAssertEqual(hardware.descriptions.first?.processes, [11])
            } else {
                try capture.start(outputDeviceID: 1, context: context).get()
                XCTAssertTrue(hardware.descriptions.first?.processes.contains(99) ?? false)
            }
            XCTAssertEqual(context.recordingFeed.driverOutputOffset, 4)
            XCTAssertEqual(context.recordingFeed.micInputOffset, 3)
            XCTAssertEqual(context.mixerInputChannelOffset, 4)
            XCTAssertEqual(hardware.defaultInputQueries, 1)
            XCTAssertEqual(hardware.aggregateDescriptions.count, 1)
            capture.stop()
            XCTAssertEqual(hardware.events.filter { $0 == "proc" }.count, 1)
        }
    }

    func testOffDoesNotResolveOrAddMicrophone() throws {
        let hardware = hardware()
        let capture = ProcessTapCapture(hardware: hardware)
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
        context.recordingConfiguration = RecordingConfiguration(enabled: false, includeMic: true)
        try capture.start(outputDeviceID: 1, context: context).get()
        XCTAssertEqual(hardware.defaultInputQueries, 0)
        XCTAssertNil(context.recordingFeed.driverOutputOffset)
        let devices = hardware.aggregateDescriptions[0][kAudioAggregateDeviceSubDeviceListKey as String] as! [[String: Any]]
        XCTAssertEqual(devices.count, 1)
        capture.stop()
    }

    func testRestartWithSameContextOffClearsRecordingTopology() throws {
        let hardware = hardware()
        let capture = ProcessTapCapture(hardware: hardware)
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
        context.recordingConfiguration = RecordingConfiguration(enabled: true, includeMic: true)
        try capture.start(outputDeviceID: 1, context: context).get()
        capture.stop()
        context.recordingConfiguration = RecordingConfiguration()
        try capture.start(outputDeviceID: 1, context: context).get()
        XCTAssertFalse(context.recordingFeed.enabled.load(ordering: .acquiring))
        XCTAssertFalse(context.recordingFeed.includeMic.load(ordering: .acquiring))
        XCTAssertNil(context.recordingFeed.driverOutputOffset)
        XCTAssertEqual(context.recordingFeed.micChannelCount, 0)
        XCTAssertEqual(hardware.defaultInputQueries, 1)
        capture.stop()
    }

    func testSelectedMicAndPhysicalDACMicOffsets() throws {
        let hardware = hardware()
        let capture = ProcessTapCapture(hardware: hardware)
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
        context.recordingConfiguration = RecordingConfiguration(enabled: true, includeMic: true, microphoneUID: "test-dac")
        try capture.start(outputDeviceID: 1, context: context).get()
        XCTAssertEqual(hardware.defaultInputQueries, 0)
        XCTAssertEqual(context.recordingFeed.micInputOffset, 0)
        XCTAssertEqual(context.mixerInputChannelOffset, 3)
        capture.stop()
    }

    func testDriverCanNeverBeSelectedAsMicrophoneOrPhysicalOutput() {
        let hardware = hardware()
        let capture = ProcessTapCapture(hardware: hardware)
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64)
        context.recordingConfiguration = RecordingConfiguration(enabled: true, includeMic: true, microphoneUID: DRIVER_DEVICE_UID)
        if case .success = capture.start(outputDeviceID: 1, context: context) { XCTFail("Driver mic must be rejected") }
        context.recordingConfiguration = RecordingConfiguration(enabled: true)
        if case .success = capture.start(outputDeviceID: 2, context: context) { XCTFail("Driver output must be rejected") }
        XCTAssertTrue(hardware.aggregateDescriptions.isEmpty)
    }
}
