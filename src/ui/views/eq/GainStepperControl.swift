// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

struct GainStepperControl: View {
    let gain: Float
    let onGainChange: (Float) -> Void

    var body: some View {
        HStack(spacing: 6) {
            StepperButton(symbol: "-", action: { adjustGain(by: -0.5) })

            InlineEditableValue(
                value: gain,
                displayFormatter: { String(format: "%+.1f dB", $0) },
                inputFormatter: { String(format: "%.1f", $0) },
                width: 54,
                alignment: .center,
                onCommit: { newValue in
                    onGainChange(EqumaczerStore.clampGain(newValue))
                }
            )
            .onTapGesture(count: 2) {
                onGainChange(0)
            }

            StepperButton(symbol: "+", action: { adjustGain(by: 0.5) })
        }
    }

    private func adjustGain(by delta: Float) {
        let snapped = Self.roundToStep(gain)
        let newValue = EqumaczerStore.clampGain(snapped + delta)
        onGainChange(Self.roundToStep(newValue))
    }

    private static func roundToStep(_ value: Float) -> Float {
        (value * 2).rounded() / 2
    }
}
