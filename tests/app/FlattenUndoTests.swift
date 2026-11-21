// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// Flatten captures a snapshot; Undo Flatten restores it exactly.
@MainActor
final class FlattenUndoTests: XCTestCase {

    func testFlattenThenUndoRestoresGains() {
        let store = EqumaczerStore()
        store.eqConfiguration.updateBandGain(index: 0, gain: 4.0)
        store.eqConfiguration.updateBandGain(index: 3, gain: -2.5)
        store.inputGain = -3
        store.outputGain = 1.5

        store.flattenBands()
        XCTAssertEqual(store.eqConfiguration.leftState.userEQ.bands[0].gain, 0)
        XCTAssertEqual(store.eqConfiguration.leftState.userEQ.bands[3].gain, 0)
        XCTAssertEqual(store.inputGain, 0)
        XCTAssertNotNil(store.lastFlattenSnapshot)

        store.undoFlatten()
        XCTAssertEqual(store.eqConfiguration.leftState.userEQ.bands[0].gain, 4.0)
        XCTAssertEqual(store.eqConfiguration.leftState.userEQ.bands[3].gain, -2.5)
        XCTAssertEqual(store.inputGain, -3)
        XCTAssertEqual(store.outputGain, 1.5)
        XCTAssertNil(store.lastFlattenSnapshot)
    }

    func testUndoWithoutFlattenIsANoOp() {
        let store = EqumaczerStore()
        store.eqConfiguration.updateBandGain(index: 1, gain: 2.0)
        store.undoFlatten()
        XCTAssertEqual(store.eqConfiguration.leftState.userEQ.bands[1].gain, 2.0)
    }
}

@MainActor
final class SoundRedoTests: XCTestCase {
    private func store() -> EqumaczerStore {
        let defaults = UserDefaults(suiteName: "equmaczer.redo.\(UUID())")!
        return EqumaczerStore(persistence: AppStatePersistence(storage: defaults), channelStore: ChannelStore(defaults: defaults), startAutomation: false)
    }
    func testNamedUndoRedoRestoresBothChannelsAndGains() {
        let store = store()
        store.channelMode = .stereo
        store.eqConfiguration.updateBandGain(index: 0, gain: 5, channel: .left)
        store.eqConfiguration.updateBandGain(index: 0, gain: -3, channel: .right)
        store.inputGain = -4
        store.flattenBands()
        XCTAssertEqual(store.undoLabel, "Flatten")
        store.undoLastAction()
        XCTAssertEqual(store.redoLabel, "Flatten")
        XCTAssertEqual(store.eqConfiguration.leftState.userEQ.bands[0].gain, 5)
        XCTAssertEqual(store.eqConfiguration.rightState.userEQ.bands[0].gain, -3)
        XCTAssertEqual(store.inputGain, -4)
        store.redoLastAction()
        XCTAssertEqual(store.eqConfiguration.leftState.userEQ.bands[0].gain, 0)
        XCTAssertEqual(store.eqConfiguration.rightState.userEQ.bands[0].gain, 0)
        XCTAssertEqual(store.inputGain, 0)
        store.undoLastAction()
        XCTAssertEqual(store.inputGain, -4)
    }
    func testNewSoundTransactionClearsRedo() {
        let store = store()
        store.flattenBands()
        store.undoLastAction()
        store.performSoundChange(label: "Band 3 gain") { $0.updateBandGain(index: 2, gain: 6) }
        XCTAssertNil(store.redoLabel)
        XCTAssertEqual(store.undoLabel, "Band 3 gain")
    }
    func testLegacyUnmatchedComparePreferenceRestoresAsMatched() {
        var snapshot = AppStateSnapshot.default
        snapshot.loudnessMatchedBypassEnabled = false
        XCTAssertTrue(EQConfiguration(from: snapshot).loudnessMatchedBypassEnabled)
    }

}
