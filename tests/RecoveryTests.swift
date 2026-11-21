import AudioTransportAtomics
import AppKit
import SwiftUI
import Atomics
import XCTest
@testable import equmaczer

@MainActor
final class RecoveryTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "equmaczer.recovery.\(UUID())")! }
    private func store() -> EqumaczerStore {
        let storage = defaults()
        return EqumaczerStore(persistence: AppStatePersistence(storage: storage), channelStore: ChannelStore(defaults: storage), startAutomation: false)
    }

    func testImportSurvivesSaveOnQuitAndIsConsumedOnce() throws {
        let storage = defaults()
        let persistence = AppStatePersistence(storage: storage)
        var incoming = AppStateSnapshot.default
        incoming.inputGain = -9
        try persistence.stageImport(incoming)
        persistence.save(.default) // ordinary save-on-quit must not replace pending import
        XCTAssertEqual(persistence.load()?.inputGain, -9)
        XCTAssertEqual(AppStatePersistence(storage: storage).load()?.inputGain, -9)
    }

    func testImportRejectsMalformedArrayState() {
        var snapshot = AppStateSnapshot.default
        snapshot.leftState.layers = []
        XCTAssertFalse(SettingsImport.isValid(snapshot))
        XCTAssertThrowsError(try AppStatePersistence(storage: defaults()).stageImport(snapshot))
    }

    func testTwoFlattenActionsHaveIndependentUndo() {
        let store = store()
        store.updateBandGain(index: 0, gain: 5)
        store.flattenBands()
        store.updateBandGain(index: 0, gain: 2)
        store.flattenBands()
        store.undoLastAction()
        XCTAssertEqual(store.eqConfiguration.bands[0].gain, 2)
        store.undoLastAction()
        XCTAssertEqual(store.eqConfiguration.bands[0].gain, 5)
    }

    func testSnapshotApplyIsOneUndoableAction() {
        let store = store()
        store.updateBandGain(index: 0, gain: 4)
        let shape = SoundCapture.capture(from: store.eqConfiguration)
        store.updateBandGain(index: 0, gain: -2)
        store.applySoundCapture(shape, label: "Snapshot")
        XCTAssertEqual(store.eqConfiguration.bands[0].gain, 4)
        XCTAssertEqual(store.undoLabel, "Snapshot")
        store.undoLastAction()
        XCTAssertEqual(store.eqConfiguration.bands[0].gain, -2)
    }

    func testBlendPreviewUsesBaselineAndCancelRestoresIt() {
        let store = store()
        store.updateBandGain(index: 0, gain: 2)
        let baseline = store.captureSoundState()
        let target = EQConfiguration()
        target.updateBandGain(index: 0, gain: 10)
        let preset = Preset(name: "Target", from: target)
        store.previewBlend(preset: preset, amount: 0.5, from: baseline)
        store.previewBlend(preset: preset, amount: 0.5, from: baseline)
        XCTAssertEqual(store.eqConfiguration.bands[0].gain, 6)
        store.restoreSoundState(baseline)
        XCTAssertEqual(store.eqConfiguration.bands[0].gain, 2)
    }

    func testScenePinIsTransientAndManualChoiceWinsRelease() {
        let store = store()
        store.channelController.setPinned(.music)
        let rules = SceneRuleStore(defaults: defaults())
        let engine = SceneEngine(rules: rules)
        engine.start(store: store)
        _ = engine.fire(SceneRule(trigger: .callApp, channel: .calls), reason: "Test")
        XCTAssertEqual(store.channelController.sceneOverride, .calls)
        XCTAssertEqual(store.channelController.state.pinned, .music)
        store.channelController.setPinned(.games)
        engine.undo()
        XCTAssertNil(store.channelController.sceneOverride)
        XCTAssertEqual(store.channelController.state.pinned, .games)
        engine.stop()
    }

    func testHourRuleUsesFullDateAndReleasesAtBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 21))!
        let rules = SceneRuleStore(defaults: defaults())
        rules.rules = [SceneRule(trigger: .hour, hour: 21, channel: .film)]
        let store = store()
        let engine = SceneEngine(rules: rules, now: { date }, calendar: calendar)
        engine.start(store: store)
        XCTAssertEqual(store.channelController.sceneOverride, .film)
        date = calendar.date(byAdding: .hour, value: 1, to: date)!
        engine.checkHour()
        XCTAssertNil(store.channelController.sceneOverride)
        date = calendar.date(from: DateComponents(year: 2026, month: 12, day: 20, hour: 21))!
        engine.checkHour()
        XCTAssertEqual(store.channelController.sceneOverride, .film)
        engine.stop()
    }

    func testModifiedShortcutsAreRejected() {
        for flag in [NSEvent.ModifierFlags.command, .control, .option, .shift] {
            XCTAssertFalse(ShortcutPolicy.isUnmodified(flag))
        }
        XCTAssertTrue(ShortcutPolicy.isUnmodified(.capsLock))
    }

    func testFullBlendRestoresBothTargetChannelsAndGains() {
        let store = store()
        store.channelMode = .stereo
        store.channelFocus = .right
        let baseline = store.captureSoundState()
        let target = EQConfiguration(initialBandCount: 4)
        target.setChannelMode(.stereo)
        target.setActiveBandCount(2, channel: .left)
        target.setActiveBandCount(3, channel: .right)
        target.updateBandGain(index: 0, gain: 7, channel: .left)
        target.updateBandGain(index: 0, gain: -4, channel: .right)
        let preset = Preset(name: "Stereo target", from: target, inputGain: -3, outputGain: -2)
        store.previewBlend(preset: preset, amount: 1, from: baseline)
        XCTAssertEqual(store.eqConfiguration.leftState.userEQ.activeBandCount, 2)
        XCTAssertEqual(store.eqConfiguration.rightState.userEQ.activeBandCount, 3)
        XCTAssertEqual(store.eqConfiguration.leftState.userEQ.bands[0].gain, 7)
        XCTAssertEqual(store.eqConfiguration.rightState.userEQ.bands[0].gain, -4)
        XCTAssertEqual(store.inputGain, -3)
        XCTAssertEqual(store.outputGain, -2)
        store.restoreSoundState(baseline)
        XCTAssertEqual(store.channelFocus, .right)
        XCTAssertEqual(store.presetManager.isModified, baseline.presetModified)
    }

    func testHourSuppressedByCallCanRunAfterCallEnds() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 20))!
        let rules = SceneRuleStore(defaults: defaults())
        rules.rules = [SceneRule(trigger: .hour, hour: 21, channel: .film)]
        let store = store()
        let engine = SceneEngine(rules: rules, now: { date }, calendar: calendar)
        engine.start(store: store)
        engine.fire(SceneRule(trigger: .callApp, channel: .calls), reason: "Call")
        date = calendar.date(byAdding: .hour, value: 1, to: date)!
        engine.checkHour()
        XCTAssertEqual(store.channelController.sceneOverride, .calls)
        engine.callChanged(false)
        engine.checkHour()
        XCTAssertEqual(store.channelController.sceneOverride, .film)
        engine.stop()
    }
}

/// The producer and consumer intentionally overlap; no semaphore serialises them.
final class PublicationRecoveryTests: XCTestCase {
    private final class ChainBox: @unchecked Sendable {
        let chain = EQChain(maxFrameCount: 64)
    }

    func testSimultaneousPublicationAndRendering() {
        let box = ChainBox()
        let done = ManagedAtomic<Bool>(false)
        let writer = expectation(description: "Writer finished")
        DispatchQueue.global().async {
            for i in 0..<10_000 {
                box.chain.stageFullUpdate(coefficients: [.identity], bypassFlags: [i % 2 == 0],
                    activeBandCount: 1, layerBypass: false)
            }
            done.store(true, ordering: .releasing)
            writer.fulfill()
        }
        var samples = [Float](repeating: 0.25, count: 64)
        repeat {
            samples.withUnsafeMutableBufferPointer {
                box.chain.applyPendingUpdates()
                box.chain.process(buffer: $0.baseAddress!, frameCount: 64)
            }
            XCTAssertTrue(samples.allSatisfy { $0 == 0.25 })
        } while !done.load(ordering: .acquiring)
        wait(for: [writer], timeout: 15)
    }

    func testC11HeaderABIAndAcquireLoads() {
        let header = UnsafeMutableRawPointer.allocate(byteCount: 64, alignment: 8)
        defer { header.deallocate() }
        audio_transport_initialize_u32(header, SharedMemoryLayout.Header.writeIndexOffset, 32768)
        audio_transport_initialize_u32(header, SharedMemoryLayout.Header.frameCountOffset, 512)
        audio_transport_initialize_f64(header, SharedMemoryLayout.Header.sampleRateOffset, 96000)
        XCTAssertEqual(audio_transport_load_acquire(header, SharedMemoryLayout.Header.writeIndexOffset), 32768)
        XCTAssertEqual(audio_transport_load_acquire(header, SharedMemoryLayout.Header.frameCountOffset), 512)
        XCTAssertEqual(audio_transport_load_f64_acquire(header, SharedMemoryLayout.Header.sampleRateOffset), 96000)
    }

    func testAudioFileHasPrivateModeAndUniqueName() throws {
        let a = try SecureAudioFile.create()
        defer { close(a.descriptor); unlink(a.path) }
        let b = try SecureAudioFile.create()
        defer { close(b.descriptor); unlink(b.path) }
        XCTAssertNotEqual(a.path, b.path)
        var info = stat()
        XCTAssertEqual(fstat(a.descriptor, &info), 0)
        XCTAssertEqual(info.st_mode & 0o777, 0o600)
        XCTAssertEqual(info.st_nlink, 1)
    }
}
