// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// C6: broad tonal approximations of classes of playback
/// systems, for checking whether a balance survives translation.
/// These are class shapes, not models of anyone's specific car
/// or phone — the surface that offers them says so, every time.
enum TranslationCheck: String, CaseIterable {
    case phone
    case laptop
    case car

    var displayName: String {
        switch self {
        case .phone: return "Phone"
        case .laptop: return "Laptop"
        case .car: return "Car"
        }
    }

    /// What the shape mimics, in one line.
    var account: String {
        switch self {
        case .phone:
            return "Lows essentially absent, mid-forward, top rolled off."
        case .laptop:
            return "Thin lows, a presence lift, slight top loss."
        case .car:
            return "Cabin bass lift, a boom-region dip, highs softened."
        }
    }

    var bands: [EQBandConfiguration] {
        switch self {
        case .phone:
            return [
                band(.lowShelf, 300, 0.7, -15),
                band(.parametric, 900, 0.7, 2),
                band(.highShelf, 11_000, 0.7, -5),
            ]
        case .laptop:
            return [
                band(.lowShelf, 250, 0.7, -10),
                band(.parametric, 3_500, 1.0, 1.5),
                band(.highShelf, 12_000, 0.7, -2),
            ]
        case .car:
            return [
                band(.lowShelf, 90, 0.7, 5),
                band(.parametric, 350, 1.0, -2),
                band(.highShelf, 9_000, 0.7, -3),
            ]
        }
    }

    private func band(_ type: FilterType, _ frequency: Float, _ q: Float, _ gain: Float) -> EQBandConfiguration {
        EQBandConfiguration(frequency: frequency, q: q, gain: gain, filterType: type, bypass: false)
    }
}
