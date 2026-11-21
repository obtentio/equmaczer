import XCTest
@testable import equmaczer

@MainActor
final class SettingsStateTests: XCTestCase {
    private func storage() -> UserDefaults {
        UserDefaults(suiteName: "equmaczer.settings-tests.\(UUID())")!
    }

    private func store(_ storage: UserDefaults) -> EqumaczerStore {
        EqumaczerStore(persistence: AppStatePersistence(storage: storage),
            channelStore: ChannelStore(defaults: storage), startAutomation: false)
    }

    func testMissingAndInvalidSavedCaptureModesRestoreTheTap() throws {
        XCTAssertEqual(store(storage()).captureMode, .processTap)
        for rawValue in [nil, -1, 999, "invalid"] as [Any?] {
            let storage = storage()
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppStateSnapshot.default)) as? [String: Any])
            json["captureMode"] = rawValue
            storage.set(try JSONSerialization.data(withJSONObject: json), forKey: "equalizer.appState")
            let restored = store(storage)
            XCTAssertEqual(restored.captureMode, .processTap)
        }
    }

    func testExplicitCapturePreferencesSurviveRestoration() {
        for mode in CaptureMode.allCases {
            let storage = storage()
            var snapshot = AppStateSnapshot.default
            snapshot.captureMode = mode.rawValue
            AppStatePersistence(storage: storage).save(snapshot)
            XCTAssertEqual(store(storage).captureMode, mode)
        }
    }

    func testLayerSwitchesSaveAndRestoreIndependently() {
        for (channel, correction) in [(false, false), (false, true), (true, false), (true, true)] {
            let storage = storage()
            let original = store(storage)
            original.channelController.enabled = channel
            original.correctionController.enabled = correction
            original.persistence.save(original.currentSnapshot)
            let restored = store(storage)
            XCTAssertEqual(restored.channelController.enabled, channel)
            XCTAssertEqual(restored.correctionController.enabled, correction)
        }
    }

    func testLegacySnapshotEnablesBothLayers() throws {
        let storage = storage()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppStateSnapshot.default)) as? [String: Any])
        json.removeValue(forKey: "channelEnabled")
        json.removeValue(forKey: "correctionEnabled")
        storage.set(try JSONSerialization.data(withJSONObject: json), forKey: "equalizer.appState")
        let restored = store(storage)
        XCTAssertTrue(restored.channelController.enabled)
        XCTAssertTrue(restored.correctionController.enabled)
    }

    func testDuringCallsUsesPersistedMode() {
        let storage = storage()
        let original = store(storage)
        XCTAssertEqual(original.autoPauseController.modeProvider?(), .lower)
        original.channelController.setDuringCalls(.pause)
        XCTAssertEqual(original.autoPauseController.modeProvider?(), .pause)
        XCTAssertEqual(store(storage).channelController.state.duringCalls, .pause)
        original.channelController.setDuringCalls(.nothing)
        XCTAssertEqual(store(storage).channelController.state.duringCalls, .nothing)
    }
}
