// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import AppKit
import SwiftUI

extension View {
    /// Tints the view with the one signal colour when it needs the user.
    /// (Was errorTint in v2; the colour is eqSignal now, never .red.)
    @ViewBuilder
    func signalTint(_ needsUser: Bool) -> some View {
        if needsUser {
            self.tint(.eqSignal)
        } else {
            self
        }
    }

    /// Bay — the raised control surface (§5.1): eqG10 fill, 10 pt
    /// corners, soft shadow. Replaces the v2 hairlineBox; separation is
    /// by surface step and shadow now, never by a stroked rectangle.
    func bay() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: EQDesign.cornerBay, style: .continuous)
                    .fill(Color.eqG10)
                    .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 8)
            )
    }

    /// Well — the recessed data surface (§5.2): eqG00, 6 pt corners,
    /// no shadow. Graphs and meters live in wells.
    func well() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: EQDesign.cornerControl, style: .continuous)
                    .fill(Color.eqG00)
            )
    }

    /// Bay label (§5.3): eqT1, sentence case, eqG60. Replaces the v2
    /// eqSectionLabel — no uppercase, no tracking, ever.
    func bayLabel() -> some View {
        self
            .font(.eqT1)
            .foregroundStyle(Color.eqG60)
    }
}

// MARK: - Design tokens v3 (UI/UX revamp plan §3, 2026-11-20)
//
// The greyscale system re-derived through the user's measured taste
// profile. Surfaces sit on the plan's OKLCH ramp exactly (chroma 0).
// Ink values are checked separately with WCAG 2 and APCA reverse-polarity
// equations. These metrics are not interchangeable. Use opaque text on
// the supported surfaces; opacity requires a new rendered contrast check.
// The v3 instrument is dark in both macOS appearances by design.

extension Color {
    private static func grey(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Acoustic void: graph plane, meter troughs, knock-out ink. Ramp L 0.14.
    static let eqG00 = grey(0x090909)
    /// Window and popover background. Ramp L 0.17.
    static let eqG05 = grey(0x0F0F0F)
    /// Bay surface: the control plane. Ramp L 0.21.
    static let eqG10 = grey(0x181818)
    /// Recessed well, slider track, 1 pt rules inside a plane. Ramp L 0.27.
    static let eqG20 = grey(0x262626)
    /// Lower data tier: spectrum depth, curve skirt. Never text. Ramp L 0.34.
    static let eqG35 = grey(0x383838)
    /// Tertiary ink: labels; reverse APCA magnitude above 60 on G00–G20.
    static let eqG60 = grey(0xB8B8B8)
    /// Secondary ink: body/readouts; reverse APCA magnitude above 75 on G00–G20.
    static let eqG80 = grey(0xD4D4D4)
    /// Primary ink and inverted active controls.
    static let eqG95 = grey(0xE4E4E4)
    /// The one red — oklch(0.62 0.19 33). Needs-you only: driver
    /// missing or old, a permission blocked. Nothing else is ever red.
    static let eqSignal = Color(red: 0xE1 / 255, green: 0x4C / 255, blue: 0x2F / 255)
}

extension Font {
    // MARK: Type scale v3 — SF Pro only, five sizes, two weights.
    // Numbers that tick use tabular figures (monospacedDigit on eqT3),
    // never a monospaced font. Sentence case everywhere; no token
    // carries uppercase or tracking.

    /// T0 — axis ticks, micro-labels (11 pt regular).
    static let eqT0 = Font.system(size: 11, weight: .regular)
    /// T1 — bay labels, control captions (11 pt semibold).
    static let eqT1 = Font.system(size: 11, weight: .semibold)
    /// T2 — body: names, settings labels, notices (13 pt regular).
    static let eqT2 = Font.system(size: 13, weight: .regular)
    /// T2 medium emphasis.
    static let eqT2Medium = Font.system(size: 13, weight: .medium)
    /// T3 — parameter readouts: gain, LUFS, route (15 pt semibold, tabular).
    static let eqT3 = Font.system(size: 15, weight: .semibold).monospacedDigit()
    /// T4 — pane titles, the one big readout (20 pt semibold).
    static let eqT4 = Font.system(size: 20, weight: .semibold)
}

extension Animation {
    /// Morph spring, re-tuned to land inside the 120–200 ms window (§3.4).
    static let eqMorph = Animation.spring(response: 0.2, dampingFraction: 0.9)
    /// Snap spring: toggles and band transitions, no wobble.
    static let eqSnap = Animation.spring(response: 0.16, dampingFraction: 0.95)
}

/// Layout and motion constants.
enum EQDesign {
    /// The fundamental spatial unit: every margin and pitch is a
    /// multiple of 4 pt (1 pt rules and 2 pt dot coordinates excepted).
    static let unit: CGFloat = 4
    /// Corners (§3.3): 6 pt controls and wells, 10 pt bays and panels,
    /// 12 pt sheets and popovers. Rounded, never square.
    static let cornerControl: CGFloat = 6
    static let cornerBay: CGFloat = 10
    static let cornerSheet: CGFloat = 12
    /// Tiling gaps (§10.1): 16 pt around the area, 8 pt between tiles.
    /// A master alone loses both and goes full-bleed (smart gaps).
    static let gapOut: CGFloat = 16
    static let gapIn: CGFloat = 8
    static let windowPadding: CGFloat = 12
    static let bayPaddingVertical: CGFloat = 10
    static let bayPaddingHorizontal: CGFloat = 12
    static let zoneAHeight: CGFloat = 44
    static let zoneBHeight: CGFloat = 148
    static let zoneCHeight: CGFloat = 81
    static let zoneDMinHeight: CGFloat = 280
    /// Per-band stagger when a preset loads or Flatten fires (6 ms, capped).
    static let rippleStep: Double = 0.006
    static let rippleCap: Double = 0.15
}
