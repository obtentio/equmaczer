// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Atomics
import CoreAudio
import XCTest
@testable import equmaczer

final class InteractiveAndBluetoothTests: XCTestCase {
    private struct MemoryAppVolumeStore: AppVolumePersisting {
        func load() -> [String: Float] { [:] }
        func save(_ volumes: [String: Float]) {}
    }

    /// Simulates dragging an EQ band slider rapidly (-12 dB -> +12 dB -> 0 dB) while
    /// ProcessTapCapture.renderSingle is actively rendering on an audio queue.
    func testRapidEQBandDragWhileRenderingIsZipperFreeAndCrashFree() {
        let frames = 128
        let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 256)
        context.useTapInputBuffers()
        context.processingMode = 1
        context.configureLoudness(sampleRate: 48000)
        context.configureLimiters(sampleRate: 48000)

        let initial = SVFMath.calculateDecrampedSVF(type: .parametric, sampleRate: 48000, frequency: 1000, q: 1.0, gain: 0)
        context.leftEQChains[0].stageFullUpdate(coefficients: [initial], bypassFlags: [false], activeBandCount: 1, layerBypass: false)
        context.rightEQChains[0].stageFullUpdate(coefficients: [initial], bypassFlags: [false], activeBandCount: 1, layerBypass: false)

        let group = DispatchGroup()
        let audioQueue = DispatchQueue(label: "test.drag.audio")
        let controlQueue = DispatchQueue(label: "test.drag.control")
        let sawNonFinite = ManagedAtomic<Bool>(false)

        group.enter()
        audioQueue.async {
            var inputBuf = [Float](repeating: 0, count: frames * 2)
            var outputBuf = [Float](repeating: 0, count: frames * 2)
            for block in 0..<400 {
                for f in 0..<frames {
                    let s = Float(0.2 * sin(2.0 * Double.pi * 1000.0 * Double(block * frames + f) / 48000.0))
                    inputBuf[f * 2] = s
                    inputBuf[f * 2 + 1] = s
                }
                inputBuf.withUnsafeMutableBufferPointer { inPtr in
                    outputBuf.withUnsafeMutableBufferPointer { outPtr in
                        var inABL = AudioBufferList(
                            mNumberBuffers: 1,
                            mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(frames * 2 * 4), mData: UnsafeMutableRawPointer(inPtr.baseAddress))
                        )
                        var outABL = AudioBufferList(
                            mNumberBuffers: 1,
                            mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(frames * 2 * 4), mData: UnsafeMutableRawPointer(outPtr.baseAddress))
                        )
                        ProcessTapCapture.renderSingle(context: context, input: &inABL, output: &outABL)
                    }
                }
                if outputBuf.contains(where: { !$0.isFinite }) {
                    sawNonFinite.store(true, ordering: .relaxed)
                }
            }
            group.leave()
        }

        group.enter()
        controlQueue.async {
            // 60 rapid slider drag ticks across -12 dB .. +12 dB .. 0 dB
            for step in 0..<60 {
                let gain = step < 30 ? (-12.0 + Double(step) * 0.8) : (12.0 - Double(step - 30) * 0.4)
                let coeffs = SVFMath.calculateDecrampedSVF(type: .parametric, sampleRate: 48000, frequency: 1000, q: 1.0, gain: gain)
                context.leftEQChains[0].stageBandUpdate(index: 0, coefficients: coeffs, bypass: false)
                context.rightEQChains[0].stageBandUpdate(index: 0, coefficients: coeffs, bypass: false)
                if step % 15 == 0 {
                    context.resetDeltaLoudness()
                }
            }
            group.leave()
        }

        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        XCTAssertFalse(sawNonFinite.load(ordering: .relaxed), "Non-finite sample emitted during live EQ band drag")
    }

    /// Verifies dragging an app volume slider does not spam route-generation bumps on every tick.
    @MainActor
    func testRapidAppVolumeDragDoesNotSpamRouteGeneration() {
        let suiteName = "equmaczer-interactive-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = EqumaczerStore(
            persistence: AppStatePersistence(storage: defaults),
            channelStore: ChannelStore(defaults: defaults),
            activityJournal: ActivityJournal(defaults: defaults),
            startAutomation: false,
            appVolumeStore: MemoryAppVolumeStore()
        )
        store.routingCoordinator.captureMode = .processTap
        store.routingCoordinator.manualModeEnabled = false

        // First move registers the app volume entry; subsequent drag ticks must not bump routeGeneration.
        store.updateAppVolume(bundleID: "com.test.player", volume: 0.9)
        let baselineGen = store.routingCoordinator.routeGeneration

        for step in 1...30 {
            let v = max(0.05, 0.9 - Float(step) * 0.025)
            store.updateAppVolume(bundleID: "com.test.player", volume: v)
        }

        XCTAssertEqual(store.routingCoordinator.routeGeneration, baselineGen,
                       "Dragging an existing app volume slider must not bump routeGeneration on every tick")
        XCTAssertEqual(store.appVolume(for: "com.test.player"), 0.15, accuracy: 0.001)
    }

    /// Simulates Bluetooth A2DP (48 kHz stereo) -> HFP/SCO (16 kHz mono) -> A2DP (48 kHz stereo):
    /// verifies -2 dBTP Bluetooth ceiling, stable 16 kHz SVF coefficients, and mono (L+R)*0.5 downmix.
    func testBluetoothA2DPToHFP16kHzMonoSwitchAndCeiling() {
        let btDevice = AudioDevice(
            id: 42,
            uid: "bt-airpods-uid",
            name: "AirPods Pro",
            transportType: kAudioDeviceTransportTypeBluetooth
        )
        XCTAssertTrue(btDevice.isBluetooth)
        XCTAssertEqual(OutputLimiterCeiling.dbTP(for: btDevice), AudioConstants.bluetoothLimiterCeilingDBTP)

        // 16 kHz HFP/SCO: verify SVF designer stays finite & stable even for high-band frequencies.
        for freq in [60.0, 250.0, 1000.0, 4000.0, 7500.0] {
            let coeffs = SVFMath.calculateDecrampedSVF(type: .parametric, sampleRate: 16000, frequency: freq, q: 1.4, gain: 6.0)
            let bq = coeffs.toBiquadCoefficients()
            XCTAssertTrue(BiquadValidator.isFinite(bq), "Non-finite SVF at 16 kHz / \(freq) Hz")
            XCTAssertTrue(BiquadValidator.isStable(bq), "Unstable SVF at 16 kHz / \(freq) Hz")
        }

        // Render mono HFP output at 16 kHz with -2 dBTP limiter ceiling and asymmetric L/R signal.
        let frames = 64
        let context = RenderCallbackContext(
            inputHALUnit: nil,
            channelCount: 2,
            maxFrameCount: 256,
            limiterCeilingDBTP: OutputLimiterCeiling.dbTP(for: btDevice)
        )
        context.useTapInputBuffers()
        context.processingMode = 1
        context.hardwareOutputChannelCount = 1
        context.configureLoudness(sampleRate: 16000)
        context.configureLimiters(sampleRate: 16000)

        var inStereo = [Float](repeating: 0, count: frames * 2)
        for i in 0..<frames {
            inStereo[i * 2] = 0.6      // Left
            inStereo[i * 2 + 1] = 0.2  // Right -> mono downmix should be ~0.4 (after 12-sample limiter lookahead)
        }
        var outMono = [Float](repeating: 0, count: frames)

        for _ in 0..<2 {
            inStereo.withUnsafeMutableBufferPointer { inPtr in
                outMono.withUnsafeMutableBufferPointer { outPtr in
                    var inABL = AudioBufferList(
                        mNumberBuffers: 1,
                        mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(frames * 2 * 4), mData: UnsafeMutableRawPointer(inPtr.baseAddress))
                    )
                    var outABL = AudioBufferList(
                        mNumberBuffers: 1,
                        mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: UnsafeMutableRawPointer(outPtr.baseAddress))
                    )
                    ProcessTapCapture.renderSingle(context: context, input: &inABL, output: &outABL)
                }
            }
        }
        XCTAssertTrue(outMono.allSatisfy { $0.isFinite })
        XCTAssertEqual(outMono[frames - 1], 0.4, accuracy: 0.02)
    }
}
