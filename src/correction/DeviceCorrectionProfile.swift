// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// A correction profile bound to one output device: a measured response
/// correction (typically an AutoEq result for a headphone), its preamp,
/// and the listener's preference trims on top.
///
/// Profiles live outside presets on purpose. A preset is a sound the
/// user dialled in; a correction is a property of the *device* — it
/// follows the headphone, not the preset, and is applied on the
/// correction layer so the two never overwrite each other.
struct DeviceCorrectionProfile: Codable, Sendable {
    /// CoreAudio UID of the output device this profile belongs to.
    var deviceUID: String

    /// Device name captured when the profile was created (for display;
    /// the UID is the identity).
    var deviceName: String

    /// Where the correction came from, e.g. "AutoEq: oratory1990 HD 650".
    var sourceName: String

    /// The correction's author, when the source names one (A7: OPRA
    /// presets carry their creator, and OPRA's CC BY-SA terms require
    /// the creator's attribution to be the prominent one). Nil for
    /// sources that don't name an author.
    var author: String? = nil

    /// The source's own description of the correction — for OPRA,
    /// its `details` text, which is where the measurement rig and
    /// the target curve live ("Harman Target • Standard",
    /// "Measured by …"). Shown verbatim: it is prose, and parsing
    /// it into structure would invent precision it doesn't have.
    var sourceDetails: String? = nil

    /// Preamp in dB (always <= 0), as published with the correction.
    var preampDB: Float

    /// Correction bands, applied in order on the correction layer.
    var bands: [PresetBand]

    /// Listener preference trim: extra low-shelf gain in dB (−10…+12).
    /// Preference research (Harman listener segments) shows most
    /// listeners want a measured correction adjusted, mainly in the bass.
    var bassTrimDB: Float = 0

    /// Listener preference trim: extra high-shelf gain in dB (±10).
    var trebleTrimDB: Float = 0

    /// Correction blend in percent (C3): how much of the measured
    /// correction is applied. Optional in storage so profiles
    /// saved before the blend existed decode as 100% — the A7
    /// author-field pattern. Use `blendFactor` at call sites.
    var blendPercent: Double? = nil

    /// The blend as a 0…1 gain factor for the profile's bands.
    var blendFactor: Float {
        Float(min(100, max(0, blendPercent ?? 100)) / 100)
    }
}

/// Persists device correction profiles in UserDefaults, keyed by
/// device UID. Small data (a handful of devices × dozens of bands),
/// so the whole map is one JSON value, like the app state snapshot.
final class DeviceCorrectionStore {
    private let defaults: UserDefaults
    private let key = "equaliser.deviceCorrections.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func profile(forUID uid: String) -> DeviceCorrectionProfile? {
        loadAll()[uid]
    }

    func save(_ profile: DeviceCorrectionProfile) {
        var all = loadAll()
        all[profile.deviceUID] = profile
        storeAll(all)
    }

    func remove(forUID uid: String) {
        var all = loadAll()
        all[uid] = nil
        storeAll(all)
    }

    private func loadAll() -> [String: DeviceCorrectionProfile] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? decoder.decode([String: DeviceCorrectionProfile].self, from: data)
        else { return [:] }
        return decoded
    }

    private func storeAll(_ all: [String: DeviceCorrectionProfile]) {
        guard let data = try? encoder.encode(all) else { return }
        defaults.set(data, forKey: key)
    }
}
