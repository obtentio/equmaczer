import CoreAudio
import Foundation
import XCTest
@testable import equmaczer

final class OutputLimiterCeilingTests: XCTestCase {
    func testTransportCeilings() {
        for transport in [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE] {
            XCTAssertEqual(OutputLimiterCeiling.dbTP(for: device(transport)), AudioConstants.bluetoothLimiterCeilingDBTP)
        }
        for transport in [kAudioDeviceTransportTypeBuiltIn, kAudioDeviceTransportTypeUSB, UInt32(0)] {
            XCTAssertEqual(OutputLimiterCeiling.dbTP(for: device(transport)), AudioConstants.limiterCeilingDBTP)
        }
        XCTAssertEqual(OutputLimiterCeiling.dbTP(for: nil), AudioConstants.limiterCeilingDBTP)
    }

    func testCeilingReachesEveryRenderLimiterAcrossDeviceChanges() {
        // Account for the independent true-peak detector's overshoot on a DC step.
        let detector = TruePeakDetector()
        let peak = (0..<64).reduce(Float(0)) { peak, _ in max(peak, detector.processSample(2)) }
        for transport in [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeBluetoothLE] {
            let ceiling = OutputLimiterCeiling.dbTP(for: device(transport))
            let context = RenderCallbackContext(inputHALUnit: nil, channelCount: 2, maxFrameCount: 64,
                                                limiterCeilingDBTP: ceiling)
            context.configureLimiters(sampleRate: 48000)
            for buffer in context.inputSampleBuffers {
                buffer.update(repeating: 2, count: 64)
            }
            for _ in 0..<100 {
                context.writeToRingBuffers(frameCount: 64)
                XCTAssertEqual(context.provideFrames(frameCount: 64), 64)
                context.processEQ(frameCount: 64)
            }
            for reduction in context.limiterGainReductionDB() {
                XCTAssertEqual(reduction, 20 * log10(peak) - ceiling, accuracy: 0.05)
            }
        }
    }

    private func device(_ transport: UInt32) -> AudioDevice {
        AudioDevice(id: 1, uid: "test", name: "Test", transportType: transport)
    }
}

final class CorrectionProfileFileTests: XCTestCase {
    func testCorrectionFilesRouteToExistingImporters() {
        XCTAssertEqual(CorrectionProfileFile.type(for: URL(fileURLWithPath: "/tmp/AutoEq.txt")), .autoEq)
        XCTAssertEqual(CorrectionProfileFile.type(for: URL(fileURLWithPath: "/tmp/AutoEq.TXT")), .autoEq)
        XCTAssertEqual(CorrectionProfileFile.type(for: URL(fileURLWithPath: "/tmp/database.jsonl")), .opra)
        XCTAssertEqual(CorrectionProfileFile.type(for: URL(fileURLWithPath: "/tmp/database.json")), .opra)
    }

    func testOtherTypesAndRemoteURLsAreRejected() {
        for name in ["song.wav", "document.pdf", "image.png", "archive.zip", "no-extension"] {
            XCTAssertNil(CorrectionProfileFile.type(for: URL(fileURLWithPath: "/tmp/" + name)))
        }
        XCTAssertNil(CorrectionProfileFile.type(for: URL(string: "https://example.com/profile.txt")!))
    }
}

@MainActor
final class LiveSettingsImportTests: XCTestCase {
    private func store() -> EqumaczerStore {
        let defaults = UserDefaults(suiteName: "equmaczer.live-import.\(UUID())")!
        return EqumaczerStore(persistence: AppStatePersistence(storage: defaults),
                              channelStore: ChannelStore(defaults: defaults), startAutomation: false)
    }

    func testImportAppliesLiveAndPersistsWithoutRestart() throws {
        let store = store()
        var incoming = store.currentSnapshot
        incoming.inputGain = -9
        incoming.outputGain = -4
        incoming.globalBypass = true
        incoming.autoPreampEnabled = false
        incoming.loudnessEnabled = true
        incoming.loudnessStrength = 0.8
        incoming.spectrumEnabled = false
        incoming.metersEnabled = false
        incoming.correctionEnabled = false
        incoming.channelEnabled = false
        incoming.channelMode = .stereo
        incoming.channelFocus = .right
        incoming.leftState.userEQ.bands[0].gain = 3
        incoming.rightState.userEQ.bands[0].gain = -6
        incoming.rightState.userEQ.activeBandCount = 32
        try store.importSettings(data: JSONEncoder().encode(incoming))
        XCTAssertEqual(store.inputGain, -9)
        XCTAssertEqual(store.outputGain, -4)
        XCTAssertTrue(store.isBypassed)
        XCTAssertFalse(store.autoPreampEnabled)
        XCTAssertTrue(store.loudnessEnabled)
        XCTAssertEqual(store.loudnessStrength, 0.8)
        XCTAssertFalse(store.spectrumEnabled)
        XCTAssertFalse(store.meterStore.metersEnabled)
        XCTAssertFalse(store.correctionController.enabled)
        XCTAssertFalse(store.channelController.enabled)
        XCTAssertEqual(store.channelMode, .stereo)
        XCTAssertEqual(store.channelFocus, .right)
        XCTAssertEqual(store.eqConfiguration.activeBandCount, 32)
        XCTAssertEqual(store.eqConfiguration.leftState.userEQ.bands[0].gain, 3)
        XCTAssertEqual(store.eqConfiguration.rightState.userEQ.bands[0].gain, -6)
        XCTAssertEqual(try encoded(store.currentSnapshot), try encoded(store.persistence.load()!))
    }

    func testUndoAndRedoRestoreWholeSettingsAndPresetContext() throws {
        let store = store()
        store.updateBandGain(index: 0, gain: 5)
        let before = store.currentSnapshot
        let name = store.presetManager.selectedPresetName
        let modified = store.presetManager.isModified
        var incoming = before
        incoming.outputGain = -12
        incoming.metersEnabled.toggle()
        incoming.autoPreampEnabled.toggle()
        incoming.leftState.userEQ.bands[0].gain = -3
        try store.importSettings(incoming)
        let after = store.currentSnapshot
        XCTAssertEqual(store.undoLabel, "Import settings")
        store.undoLastAction()
        XCTAssertEqual(try encoded(store.currentSnapshot), try encoded(before))
        XCTAssertEqual(store.presetManager.selectedPresetName, name)
        XCTAssertEqual(store.presetManager.isModified, modified)
        store.redoLastAction()
        XCTAssertEqual(try encoded(store.currentSnapshot), try encoded(after))
        XCTAssertEqual(try encoded(store.persistence.load()!), try encoded(after))
    }

    func testInvalidImportChangesNeitherLiveStatePersistenceNorUndo() throws {
        let store = store()
        store.updateBandGain(index: 0, gain: 2)
        store.persistence.save(store.currentSnapshot)
        let before = try encoded(store.currentSnapshot)
        let undoLabel = store.undoLabel
        var invalid = store.currentSnapshot
        invalid.outputGain = -12
        invalid.rightState.layers = []
        XCTAssertThrowsError(try store.importSettings(invalid))
        XCTAssertEqual(try encoded(store.currentSnapshot), before)
        XCTAssertEqual(try encoded(store.persistence.load()!), before)
        XCTAssertEqual(store.undoLabel, undoLabel)
    }

    func testInvalidFilesLeaveSettingsAndUndoUntouched() throws {
        let store = store()
        let before = try encoded(store.currentSnapshot)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: before) as? [String: Any])
        json["captureMode"] = 999
        let invalidRouting = try JSONSerialization.data(withJSONObject: json)
        for data in [Data("not JSON".utf8), invalidRouting, Data(repeating: 32, count: 2_000_001)] {
            XCTAssertThrowsError(try store.importSettings(data: data)) { error in
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
            XCTAssertEqual(try encoded(store.currentSnapshot), before)
            XCTAssertNil(store.undoLabel)
        }
    }

    private func encoded(_ snapshot: AppStateSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(snapshot)
    }
}
