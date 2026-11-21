// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation
import os.log

/// The hearing layer's state (A5): relative per-ear adjustments,
/// tuned by ear. These are adjustments, not measurements — nothing
/// here claims to describe the listener's hearing, and the pane
/// says so. One profile: hearing follows the person, not the
/// output device.
struct HearingState: Codable, Equatable {
    var enabled = false
    var leftLowDB: Float = 0
    var leftHighDB: Float = 0
    var rightLowDB: Float = 0
    var rightHighDB: Float = 0
    /// An entered audiogram (optional, so older saved state decodes).
    var audiogram: Audiogram?

    /// True when the layer follows an entered, in-use audiogram
    /// rather than the by-ear shelves.
    var usesAudiogram: Bool {
        guard let audiogram else { return false }
        return audiogram.inUse && !audiogram.enteredEars.isEmpty
    }

    /// Where the layer's curve comes from, for the Layers row.
    var sourceLabel: String {
        guard usesAudiogram, let audiogram else { return "by-ear test" }
        return "audiogram, " + audiogram.enteredEars.map(\.letter).joined(separator: "/")
    }

    /// The slider range, symmetric: boost a weaker side, or cut a
    /// more sensitive one.
    static let rangeDB: ClosedRange<Float> = -12...12

    mutating func reset() {
        leftLowDB = 0
        leftHighDB = 0
        rightLowDB = 0
        rightHighDB = 0
        audiogram = nil
    }
}

/// Pure per-ear composition of the hearing layer, at the correction
/// composer's own shelf constants so every broad shelf in the app
/// shares one shape. Zero gains are omitted; a disabled layer
/// composes empty for both ears.
enum HearingComposition {
    static func bands(lowDB: Float, highDB: Float) -> [EQBandConfiguration] {
        var bands: [EQBandConfiguration] = []
        if lowDB != 0 {
            bands.append(EQBandConfiguration(
                frequency: CorrectionComposer.lowShelfHz, q: CorrectionComposer.shelfQ,
                gain: lowDB, filterType: .lowShelf, bypass: false
            ))
        }
        if highDB != 0 {
            bands.append(EQBandConfiguration(
                frequency: CorrectionComposer.highShelfHz, q: CorrectionComposer.shelfQ,
                gain: highDB, filterType: .highShelf, bypass: false
            ))
        }
        return bands
    }

    static func leftBands(for state: HearingState) -> [EQBandConfiguration] {
        guard state.enabled else { return [] }
        if state.usesAudiogram, let audiogram = state.audiogram { return audiogram.bands(for: .left) }
        return bands(lowDB: state.leftLowDB, highDB: state.leftHighDB)
    }

    static func rightBands(for state: HearingState) -> [EQBandConfiguration] {
        guard state.enabled else { return [] }
        if state.usesAudiogram, let audiogram = state.audiogram { return audiogram.bands(for: .right) }
        return bands(lowDB: state.rightLowDB, highDB: state.rightHighDB)
    }
}

/// UserDefaults persistence for `HearingState`, following the
/// `ChannelStore` pattern (JSON under one key, injectable defaults).
final class HearingStore {
    private let defaults: UserDefaults
    private let key = "equaliser.hearing.v1"
    private let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "HearingStore")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> HearingState {
        guard let data = defaults.data(forKey: key) else { return HearingState() }
        do {
            return try JSONDecoder().decode(HearingState.self, from: data)
        } catch {
            logger.error("Failed to decode hearing state: \(error.localizedDescription)")
            return HearingState()
        }
    }

    func save(_ state: HearingState) {
        do {
            let data = try JSONEncoder().encode(state)
            defaults.set(data, forKey: key)
        } catch {
            logger.error("Failed to encode hearing state: \(error.localizedDescription)")
        }
    }
}
