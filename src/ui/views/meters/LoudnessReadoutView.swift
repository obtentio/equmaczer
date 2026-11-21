// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// Programme loudness readout: BS.1770 integrated loudness of the
/// processed output, short-term loudness, and the bypass-match gain
/// in effect on the flat-compare path when one has been measured.
/// Stacked mono rows — the previous single-line form truncated in
/// the monitor column.
struct LoudnessReadoutView: View {
    @ObservedObject var meterStore: MeterStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let integrated = meterStore.integratedLUFS {
                row(label: "INTEGRATED", value: String(format: "%.1f LUFS", integrated))
            }
            if let shortTerm = meterStore.shortTermLUFS {
                row(label: "SHORT-TERM", value: String(format: "%.1f LUFS", shortTerm))
            }
            if meterStore.integratedLUFS == nil && meterStore.shortTermLUFS == nil {
                Text("Awaiting programme")
                    .font(.eqT0)
                    .foregroundStyle(Color.eqG60)
            }
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.eqT1)
                .foregroundStyle(Color.eqG60)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.eqT3)
                .foregroundStyle(Color.eqG95)
        }
    }
}
