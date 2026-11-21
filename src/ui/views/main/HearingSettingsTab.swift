// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// The Hearing pane (A5): relative per-ear Low/High adjustments.
/// The framing is part of the feature and sits at the top of the
/// pane, not in a footnote: these are adjustments tuned by ear,
/// never a measurement of anyone's hearing.
struct HearingSettingsTab: View {
    @ObservedObject var controller: HearingController
    @ObservedObject var doseController: DoseController
    @EnvironmentObject var store: EqumaczerStore
    @State private var showRitual = false
    @State private var section: String

    init(controller: HearingController, doseController: DoseController, initialSection: String = "Adjustments") {
        self.controller = controller
        self.doseController = doseController
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Hearing section", selection: $section) {
                Text("Adjustments").tag("Adjustments")
                Text("Audiogram").tag("Audiogram")
                Text("Estimated dose").tag("Dose")
            }.pickerStyle(.segmented).padding(.bottom, 12)
            if section == "Adjustments" {

            Text("Relative adjustments, tuned by ear — not a hearing measurement. Headphones and volume change what you hear, so set each side where speech and music sound balanced to you.")
                .font(.eqT2)
                .foregroundStyle(Color.eqG60)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            SettingsRow(label: "Hearing layer") {
                Toggle("", isOn: enabledBinding)
                    .labelsHidden()
            }

            SettingsRow(label: "Source", caption: "Where the layer's curve comes from") {
                HStack(spacing: 10) {
                    Text(controller.state.sourceLabel)
                        .font(.eqT2Medium)
                        .foregroundStyle(Color.eqG95)
                    Button("Enter audiogram…") { section = "Audiogram" }
                }
            }

            SettingsRow(label: "Setup") {
                Button("Guided setup…") { showRitual = true }
                    .help("Pre-flight checks, a named scope, then the shelves one at a time — each confirmed before the next")
            }
            .sheet(isPresented: $showRitual) {
                HearingRitualView(store: store, controller: controller)
            }

            SettingsSectionHeader(title: "Left ear")
            earSliders(
                low: controller.state.leftLowDB,
                high: controller.state.leftHighDB,
                onLow: { controller.setLeftLow($0) },
                onHigh: { controller.setLeftHigh($0) }
            )
            .disabled(!controller.state.enabled)

            SettingsSectionHeader(title: "Right ear")
            earSliders(
                low: controller.state.rightLowDB,
                high: controller.state.rightHighDB,
                onLow: { controller.setRightLow($0) },
                onHigh: { controller.setRightHigh($0) }
            )
            .disabled(!controller.state.enabled)

            Button("Reset both ears") { controller.reset() }
                .padding(.top, 12)
                .disabled(!controller.state.enabled || isFlat)

            } else if section == "Audiogram" { audiogramSection } else { doseSection }
            Spacer(minLength: 0)
        }
    }

    /// The week's estimated dose (A6): seven day bars and the total
    /// against the WHO–ITU weekly reference, with the estimate's
    /// anchor stated on the surface.
    private var doseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(title: "This week — estimated dose")
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(doseController.week) { day in
                    VStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.eqG60)
                            .frame(width: 24, height: barHeight(for: day.fraction))
                        Text(day.label)
                            .font(.eqT0)
                            .foregroundStyle(Color.eqG60)
                    }
                }
            }
            .padding(.vertical, 8)
            Text(String(format: "About %.0f%% of the weekly reference — 80 dBA for 40 hours.", doseController.weeklyPercent))
                .font(.eqT2)
                .foregroundStyle(Color.eqG95)
            Text("Estimate: full-scale output at full volume counts as 100 dBA. Your headphones and volume change the real level.")
                .font(.eqT2)
                .foregroundStyle(Color.eqG60)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.top, 8)
    }

    /// Enter an audiogram per ear (A6): standard audiometric
    /// frequencies, dB HL. The layer then compensates each ear from
    /// its own thresholds.
    private var audiogramSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("An estimate, not medical advice. Enter thresholds from your own audiogram, in dB HL. The layer boosts each ear by half of any loss above \(Int(Audiogram.normalLimitDB)) dB HL, up to \(Int(HearingState.rangeDB.upperBound)) dB. It is not a diagnosis or a prescription; see a hearing professional for either.")
                .font(.eqT2)
                .foregroundStyle(Color.eqG60)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
            SettingsRow(label: "Use audiogram", caption: "Off returns the layer to its by-ear shelves") {
                Toggle("", isOn: Binding(
                    get: { controller.state.audiogram?.inUse ?? false },
                    set: { controller.setAudiogramInUse($0) }
                ))
                .labelsHidden()
                .disabled(controller.state.audiogram == nil)
            }
            HStack(alignment: .top, spacing: 32) {
                ForEach(HearingEar.allCases, id: \.self) { ear in
                    VStack(alignment: .leading, spacing: 4) {
                        SettingsSectionHeader(title: ear == .left ? "Left ear" : "Right ear")
                        ForEach(Audiogram.frequencies.indices, id: \.self) { index in
                            thresholdRow(ear: ear, index: index)
                        }
                    }
                }
            }
            Button("Clear audiogram") { controller.clearAudiogram() }
                .padding(.top, 12)
                .disabled(controller.state.audiogram == nil)
        }
    }

    private func thresholdRow(ear: HearingEar, index: Int) -> some View {
        let frequency = Audiogram.frequencies[index]
        let value = controller.state.audiogram?.thresholds(for: ear)[index] ?? 0
        return HStack(spacing: 8) {
            Text(frequency >= 1000 ? "\(Int(frequency / 1000)) kHz" : "\(Int(frequency)) Hz")
                .font(.eqT2)
                .foregroundStyle(Color.eqG95)
                .frame(width: 56, alignment: .leading)
            Stepper(value: Binding(
                get: { value },
                set: { controller.setAudiogramThreshold($0, ear: ear, index: index) }
            ), in: Audiogram.rangeDB, step: Audiogram.stepDB) {
                Text(String(format: "%.0f dB HL", value))
                    .font(.eqT2)
                    .monospacedDigit()
            }
        }
    }

    private func barHeight(for fraction: Double) -> CGFloat {
        guard fraction > 0 else { return 0 }
        // A day spending a seventh of the weekly budget fills the bar.
        return CGFloat(min(36, max(2, fraction * 250)))
    }

    private var isFlat: Bool {
        controller.state.leftLowDB == 0
            && controller.state.leftHighDB == 0
            && controller.state.rightLowDB == 0
            && controller.state.rightHighDB == 0
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { controller.state.enabled },
            set: { controller.setEnabled($0) }
        )
    }

    private func earSliders(low: Float, high: Float, onLow: @escaping (Float) -> Void, onHigh: @escaping (Float) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            shelfSlider(label: "Low", value: low, onChange: onLow)
            shelfSlider(label: "High", value: high, onChange: onHigh)
        }
        .padding(.vertical, 6)
    }

    private func shelfSlider(label: String, value: Float, onChange: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.eqT2)
                .foregroundStyle(Color.eqG95)
                .frame(width: 44, alignment: .leading)
            Slider(
                value: Binding(get: { value }, set: { onChange($0) }),
                in: HearingState.rangeDB,
                step: 0.5
            )
            Text(String(format: "%+.1f dB", value))
                .font(.eqT2)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
    }
}
