// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// The Driver pane's proof of processing (B2): measured signal in,
/// measured signal out, the measured loudness effect of the EQ
/// path, and the verdict those facts support. Refreshes once a
/// second while the pane is on screen — the meter tick sleeps when
/// the main window is closed, and this is where a user comes to
/// check exactly then.
struct ProcessingProofSection: View {
    @ObservedObject var store: EqumaczerStore
    @ObservedObject var meterStore: MeterStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(title: "Processing proof")

            SettingsRow(label: "Signal in") {
                Text(String(format: "%.1f dB", meterStore.proofInputRMSDB))
                    .font(.eqT2Medium)
                    .foregroundStyle(Color.eqG95)
            }

            SettingsRow(label: "Signal out") {
                Text(String(format: "%.1f dB", meterStore.proofOutputRMSDB))
                    .font(.eqT2Medium)
                    .foregroundStyle(Color.eqG95)
            }

            SettingsRow(label: "Measured effect", caption: "Loudness the EQ path adds, pre against post") {
                Text(meterStore.proofEffectLU.map { String(format: "%+.1f LU", $0) } ?? "—")
                    .font(.eqT2Medium)
                    .foregroundStyle(Color.eqG95)
            }

            Text(verdict.line)
                .font(.eqT2)
                .foregroundStyle(Color.eqG60)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
        }
        .task {
            while !Task.isCancelled {
                meterStore.refreshProcessingProof()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private var verdict: ProcessingProof.Verdict {
        ProcessingProof.verdict(
            routingActive: store.routingStatus.isActive,
            bypassed: store.eqConfiguration.globalBypass,
            comparingFlat: store.compareMode == .flat,
            matchEnabled: store.loudnessMatchedBypassEnabled,
            inputRMSDB: meterStore.proofInputRMSDB,
            outputRMSDB: meterStore.proofOutputRMSDB,
            effectLU: meterStore.proofEffectLU
        )
    }
}
