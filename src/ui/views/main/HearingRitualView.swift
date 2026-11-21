// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// C5: the hearing setup as a ritual — pre-flight, scope, an
/// ordered tune, a summary. Dirac's lesson applied honestly:
/// the gates check conditions, never pretend to measure. The
/// step chips are all live, so a returning user jumps straight
/// to the step that changed.
struct HearingRitualView: View {
    @ObservedObject var store: EqumaczerStore
    @ObservedObject var controller: HearingController

    @State private var ritual = HearingRitual()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader
            switch ritual.step {
            case .preflight: preflightStep
            case .scope: scopeStep
            case .tune: tuneStep
            case .done: doneStep
            }
        }
        .padding(16)
        .frame(width: 420)
        .task {
            while !Task.isCancelled {
                store.meterStore.refreshProcessingProof()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Header

    private var stepHeader: some View {
        HStack(spacing: 6) {
            ForEach(HearingRitual.Step.allCases, id: \.self) { step in
                Button {
                    ritual.goTo(step)
                } label: {
                    Text("\(step.rawValue) \(stepName(step))")
                        .font(.eqT1)
                        .foregroundStyle(ritual.step == step ? Color.eqG95 : Color.eqG60)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ritual.step == step ? Color.eqG20 : Color.clear)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func stepName(_ step: HearingRitual.Step) -> String {
        switch step {
        case .preflight: return "Pre-flight"
        case .scope: return "Scope"
        case .tune: return "Tune"
        case .done: return "Done"
        }
    }

    // MARK: - Step 1: pre-flight

    private var preflight: RitualPreflight.Evaluation {
        RitualPreflight.evaluate(
            routingActive: store.routingStatus.isActive,
            inputRMSDB: store.meterStore.proofInputRMSDB,
            layerEnabled: controller.state.enabled
        )
    }

    private var preflightStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            checkRow("Audio is routing", ok: preflight.routingActive)
            checkRow("Music is reaching equmaczer", ok: preflight.signalArriving)
            HStack(spacing: 8) {
                Text(preflight.layerEnabled ? "✓" : "·")
                    .foregroundStyle(Color.eqG95)
                Text("Hearing layer is on")
                    .font(.eqT2)
                    .foregroundStyle(Color.eqG95)
                if !preflight.layerEnabled {
                    Button("Turn it on") { controller.setEnabled(true) }
                        .font(.eqT1)
                }
            }
            Text("Set the volume where you normally listen, and leave it there while you tune. Play something with voices — speech is the easiest thing to judge.")
                .font(.eqT2)
                .foregroundStyle(Color.eqG60)
                .fixedSize(horizontal: false, vertical: true)
            Button("Continue") { ritual.goTo(.scope) }
                .disabled(!preflight.canProceed)
            if !preflight.canProceed {
                Text("The checks above unlock Continue — tuning a layer you cannot hear would be guessing.")
                    .font(.eqT0)
                    .foregroundStyle(Color.eqG60)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func checkRow(_ label: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Text(ok ? "✓" : "·")
                .foregroundStyle(Color.eqG95)
            Text(label)
                .font(.eqT2)
                .foregroundStyle(ok ? Color.eqG95 : Color.eqG60)
        }
    }

    // MARK: - Step 2: scope

    private var scopeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ears")
                .font(.eqT1)
                .foregroundStyle(Color.eqG60)
            optionButton("Each ear separately", selected: ritual.ears == .separately) {
                ritual.ears = .separately
            }
            optionButton("Both ears together", selected: ritual.ears == .together) {
                ritual.ears = .together
            }
            Text("Length")
                .font(.eqT1)
                .foregroundStyle(Color.eqG60)
            optionButton("Quick — one pass", selected: ritual.passes == 1) {
                ritual.passes = 1
            }
            optionButton("Full — two passes", selected: ritual.passes == 2) {
                ritual.passes = 2
            }
            Text("The second pass re-presents each shelf after you have heard the whole set once.")
                .font(.eqT0)
                .foregroundStyle(Color.eqG60)
                .fixedSize(horizontal: false, vertical: true)
            Button("Start tuning") { ritual.goTo(.tune) }
        }
    }

    private func optionButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.eqT2)
                .foregroundStyle(Color.eqG95)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? Color.eqG20 : Color.eqG10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 3: tune

    @ViewBuilder
    private var tuneStep: some View {
        if !controller.state.enabled {
            VStack(alignment: .leading, spacing: 10) {
                Text("The hearing layer is off — there is nothing to tune yet.")
                    .font(.eqT2)
                    .foregroundStyle(Color.eqG80)
                Button("Turn it on") { controller.setEnabled(true) }
            }
        } else if let shelf = ritual.currentShelf {
            VStack(alignment: .leading, spacing: 10) {
                if ritual.passes == 2 {
                    Text("Pass \(ritual.pass) of 2")
                        .font(.eqT0)
                        .foregroundStyle(Color.eqG60)
                }
                Text(shelf.label)
                    .font(.eqT3)
                    .foregroundStyle(Color.eqG95)
                shelfSlider(for: shelf)
                Text("Move it until this range sounds right, or leave it where it is — confirming is the step, adjusting is optional.")
                    .font(.eqT0)
                    .foregroundStyle(Color.eqG60)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Sounds right") { ritual.confirmShelf() }
            }
        }
    }

    private func shelfSlider(for shelf: HearingRitual.Shelf) -> some View {
        let (value, set): (Float, (Float) -> Void) = {
            switch shelf {
            case .bothLow:
                return (controller.state.leftLowDB, { controller.setLeftLow($0); controller.setRightLow($0) })
            case .bothHigh:
                return (controller.state.leftHighDB, { controller.setLeftHigh($0); controller.setRightHigh($0) })
            case .leftLow:
                return (controller.state.leftLowDB, { controller.setLeftLow($0) })
            case .leftHigh:
                return (controller.state.leftHighDB, { controller.setLeftHigh($0) })
            case .rightLow:
                return (controller.state.rightLowDB, { controller.setRightLow($0) })
            case .rightHigh:
                return (controller.state.rightHighDB, { controller.setRightHigh($0) })
            }
        }()
        return HStack(spacing: 8) {
            Slider(
                value: Binding(get: { value }, set: { set($0) }),
                in: HearingState.rangeDB,
                step: 0.5
            )
            Text(String(format: "%+.1f dB", value))
                .font(.eqT2)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
    }

    // MARK: - Step 4: done

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryRow("Left — Low", controller.state.leftLowDB)
            summaryRow("Left — High", controller.state.leftHighDB)
            summaryRow("Right — Low", controller.state.rightLowDB)
            summaryRow("Right — High", controller.state.rightHighDB)
            Text("Saved as you went. Rerun anytime — the steps above jump straight to Tune.")
                .font(.eqT0)
                .foregroundStyle(Color.eqG60)
                .padding(.top, 4)
            Button("Done") { dismiss() }
        }
    }

    private func summaryRow(_ label: String, _ value: Float) -> some View {
        HStack {
            Text(label)
                .font(.eqT2)
                .foregroundStyle(Color.eqG60)
            Spacer()
            Text(String(format: "%+.1f dB", value))
                .font(.eqT2)
                .foregroundStyle(Color.eqG95)
        }
    }
}
