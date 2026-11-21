import XCTest
import SwiftUI
@testable import equmaczer

/// Regression contracts first reproduced during the independent audit.
@MainActor
final class RevampRegressionTests: XCTestCase {
    func testZeroBlendPreservesBandsAndBypass() {
        let storage = UserDefaults(suiteName: "equmaczer.audit.\(UUID())")!
        let store = EqumaczerStore(persistence: AppStatePersistence(storage: storage))
        store.bandCount = 10
        store.updateBandBypass(index: 0, bypass: true)
        let target = EQConfiguration(initialBandCount: 3)
        applyBlend(store: store, preset: Preset(name: "Audit", from: target), blend: 0)
        XCTAssertEqual(store.bandCount, 10)
        XCTAssertTrue(store.eqConfiguration.bands[0].bypass)
    }

    func testPanicFlattenClearsBothStereoChannels() {
        let storage = UserDefaults(suiteName: "equmaczer.audit.\(UUID())")!
        let store = EqumaczerStore(persistence: AppStatePersistence(storage: storage))
        store.channelMode = .stereo
        store.channelFocus = .left
        store.eqConfiguration.updateBandGain(index: 0, gain: 6, channel: .left)
        store.eqConfiguration.updateBandGain(index: 0, gain: -3, channel: .right)
        store.flattenBands()
        XCTAssertEqual(store.eqConfiguration.rightState.userEQ.bands[0].gain, 0)
    }

    func testPresetLoadWithRightFocusWritesLeftChannel() {
        let config = EQConfiguration(initialBandCount: 3)
        config.setChannelMode(.stereo)
        config.channelFocus = .right
        let preset = Preset(metadata: PresetMetadata(name: "Audit stereo"), settings: PresetSettings(channelMode: "stereo", leftBands: [PresetBand(frequency: 100, q: 1, gain: 6, filterType: .parametric, bypass: false)], rightBands: [PresetBand(frequency: 200, q: 1, gain: -3, filterType: .parametric, bypass: false)]))
        let manager = PresetManager()
        manager.applyPreset(preset, to: config)
        XCTAssertEqual(config.leftState.userEQ.bands[0].gain, 6)
    }
}
