// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// Design System v2 primitives: brutalist skeleton, normcore
/// controls, polarity instead of hue. State flips are single-frame
/// step functions — nothing in the chrome animates.

/// A 1 pt structural rule in G20. Full-bleed by default.
struct StructuralRule: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(Color.eqG20)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// The [ ON ] / [ OFF ] polarity toggle: solid chalk when on,
/// hollow well when off. Instant inversion, no transition.
struct PolarityToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isOn ? "ON" : "OFF")
                .font(.eqT1)
                .frame(minWidth: 36)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .background(isOn ? Color.eqG95 : Color.eqG10)
        .foregroundStyle(isOn ? Color.eqG00 : Color.eqG80)
        .overlay(
            RoundedRectangle(cornerRadius: EQDesign.cornerControl)
                .strokeBorder(isOn ? Color.clear : Color.eqG20, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: EQDesign.cornerControl))
        .animation(nil, value: isOn)
    }
}

/// A preset capsule: chalk-solid when selected, hollow well
/// otherwise, with a 2 pt G95 border when its preset is modified.
struct CapsuleButton: View {
    let label: String
    let isSelected: Bool
    var isModified: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.eqT1)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.eqG95 : Color.eqG10)
        .foregroundStyle(isSelected ? Color.eqG00 : Color.eqG80)
        .overlay(
            RoundedRectangle(cornerRadius: EQDesign.cornerControl)
                .strokeBorder(
                    isModified ? Color.eqG95 : (isSelected ? Color.clear : Color.eqG20),
                    lineWidth: isModified ? 2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: EQDesign.cornerControl))
        .animation(nil, value: isSelected)
    }
}

/// The 7×7 dot-matrix EQ arc — the app's emblem, drawn in the
/// lattice language: heights [3,5,4,6,7,5,3], chalk dots on void,
/// unlit positions as G20 pins.
struct DotArcMark: View {
    /// Size of one cell in points; the mark is 7 cells square.
    var cell: CGFloat = 4

    private static let heights = [3, 5, 4, 6, 7, 5, 3]

    var body: some View {
        Canvas { context, size in
            let step = size.width / 7
            for column in 0..<7 {
                for row in 0..<7 {
                    let lit = row >= 7 - Self.heights[column]
                    let inset = step * 0.18
                    let rect = CGRect(
                        x: CGFloat(column) * step + inset,
                        y: CGFloat(row) * step + inset,
                        width: step - inset * 2,
                        height: step - inset * 2
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: step * 0.12),
                        with: .color(lit ? .eqG95 : .eqG20)
                    )
                }
            }
        }
        .frame(width: cell * 7, height: cell * 7)
        .background(Color.eqG00)
    }
}
