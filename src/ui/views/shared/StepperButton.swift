// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// A stepper half in the v2 language: G10 well, hairline border,
/// chalk glyph. Shared by the gain steppers.
struct StepperButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(symbol == "+" ? "+" : "−")
                .font(.eqT2Medium)
                .foregroundStyle(Color.eqG95)
                .frame(width: 24, height: 20)
        }
        .buttonStyle(.plain)
        .background(Color.eqG10)
        .overlay(
            RoundedRectangle(cornerRadius: EQDesign.cornerControl)
                .strokeBorder(Color.eqG20, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: EQDesign.cornerControl))
    }
}
