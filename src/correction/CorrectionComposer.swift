// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// Pure composition of the correction layer's band list.
///
/// Three inputs, one owner, one ordered output:
/// 1. Loudness shelves (present only when loudness compensation is on
///    and the output is at an audible volume below the reference level)
/// 2. The device profile's measured correction bands
/// 3. The listener's preference trims (shelves, present only when the
///    trim is non-zero and a profile exists to attach them to)
///
/// Kept pure — no device access, no state — so the composition rules
/// are unit-testable without any audio machinery.
enum CorrectionComposer {
    /// Profile bands are capped so profile + loudness (2) + trims (2)
    /// always fit the chain's 64-band budget.
    static let maxProfileBands = 58

    /// Shelf shapes shared by the loudness shelves and the trims.
    static let lowShelfHz: Float = 105
    static let highShelfHz: Float = 10_000
    static let shelfQ: Float = 0.9

    /// Below this volume scalar the output is effectively silent;
    /// compensation is held at zero so unmuting never meets a
    /// fully-boosted correction at a stale level.
    static let audibleVolumeFloor: Float = 0.005

    static func composeBands(
        profile: DeviceCorrectionProfile?,
        loudnessEnabled: Bool,
        volumeScalar: Float?,
        loudnessStrength: Float
    ) -> [EQBandConfiguration] {
        var bands: [EQBandConfiguration] = []

        if loudnessEnabled, let volume = volumeScalar, volume >= audibleVolumeFloor {
            let phon = LoudnessCompensation.estimatedPhon(volumeScalar: volume)
            let gains = LoudnessCompensation.compensation(
                phons: phon,
                strength: Double(loudnessStrength)
            )
            if gains.lowDB > 0.05 {
                bands.append(EQBandConfiguration(
                    frequency: lowShelfHz, q: shelfQ, gain: Float(gains.lowDB),
                    filterType: .lowShelf, bypass: false
                ))
            }
            if gains.highDB > 0.05 {
                bands.append(EQBandConfiguration(
                    frequency: highShelfHz, q: shelfQ, gain: Float(gains.highDB),
                    filterType: .highShelf, bypass: false
                ))
            }
        }

        if let profile {
            // C3: the blend scales the correction's own bands —
            // never the listener's trims below or the loudness
            // shelves above, which are dialled in absolute terms.
            let blend = profile.blendFactor
            for band in profile.bands.prefix(maxProfileBands) {
                bands.append(EQBandConfiguration(
                    frequency: band.frequency, q: band.q, gain: band.gain * blend,
                    filterType: band.filterType, bypass: band.bypass
                ))
            }
            if profile.bassTrimDB != 0 {
                bands.append(EQBandConfiguration(
                    frequency: lowShelfHz, q: shelfQ, gain: profile.bassTrimDB,
                    filterType: .lowShelf, bypass: false
                ))
            }
            if profile.trebleTrimDB != 0 {
                bands.append(EQBandConfiguration(
                    frequency: highShelfHz, q: shelfQ, gain: profile.trebleTrimDB,
                    filterType: .highShelf, bypass: false
                ))
            }
        }

        return bands
    }
}
