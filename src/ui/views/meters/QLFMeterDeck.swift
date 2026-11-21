// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// The meter deck in the lattice language: four horizontal QLF
/// tracks (input/output × L/R) plus the limiter's gain-reduction
/// track. Each signal track carries three facts in three tiers —
/// the RMS body in G60, the peak frontier in G80, and the held
/// peak as a single G95 column — over the app's −36…0 dB meter
/// range, with the tick's peak as a numeric readout. Replaces the
/// vertical NSView meter stacks; the ballistics and the gamma
/// curve are the meter store's own normalised positions.
struct QLFMeterDeck: View {
    @ObservedObject var meterStore: MeterStore
    /// Stereo mode shows both limiter channels; linked shows one.
    let isStereo: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            track(label: "IN L", index: 0)
            track(label: "IN R", index: 1)
            track(label: "OUT L", index: 2)
            track(label: "OUT R", index: 3)
            scaleRow
            grTrack
        }
    }

    private func track(label: String, index: Int) -> some View {
        let enabled = meterStore.metersEnabled
        let peak = enabled ? meterStore.peakPositions[index] : 0
        let hold = enabled ? meterStore.peakHoldPositions[index] : 0
        let rms = enabled ? meterStore.rmsPositions[index] : 0
        let readout = enabled ? meterStore.peakReadoutsDB[index] : -36
        return HStack(spacing: 6) {
            Text(label)
                .font(.eqT0)
                .foregroundStyle(Color.eqG60)
                .frame(width: 40, alignment: .leading)
            Canvas { context, size in
                var collector = QLFCollector()
                let cells = max(1, Int(size.width / QLFLattice.cellSize))
                let rmsOccupancy = QLFLattice.barOccupancy(value: Double(rms), cells: cells)
                let peakOccupancy = QLFLattice.barOccupancy(value: Double(peak), cells: cells)
                for column in 0..<cells {
                    for row in 0..<3 {
                        collector.addCell(column: column, row: row,
                                          occupancy: rmsOccupancy[column], tier: .tier60)
                        collector.addCell(column: column, row: row,
                                          occupancy: peakOccupancy[column], tier: .tier80)
                    }
                }
                // Held peak: one full chalk column at its position.
                if hold > 0.01 {
                    let holdColumn = min(cells - 1, Int(Double(hold) * Double(cells)))
                    for row in 0..<3 {
                        collector.addCell(column: holdColumn, row: row, occupancy: 1, tier: .tier95)
                    }
                }
                collector.fill(into: context)
            }
            .frame(height: 12)
            .background(Color.eqG00)
            Text(String(format: "%.1f", max(-36, readout)))
                .font(.eqT2)
                .foregroundStyle(Color.eqG80)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private var scaleRow: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 40)
            HStack {
                Text("−36")
                Spacer()
                Text("−18")
                Spacer()
                Text("0")
            }
            .font(.eqT0)
            .foregroundStyle(Color.eqG60)
            Spacer().frame(width: 38)
        }
    }

    /// Gain reduction grows right-to-left on a 0…−18 dB scale;
    /// the readout keeps the shipped per-channel form.
    private var grTrack: some View {
        let gr = meterStore.limiterGainReductionDB
        let magnitude = gr.max() ?? 0
        return HStack(spacing: 6) {
            Text("LIM")
                .font(.eqT0)
                .foregroundStyle(Color.eqG60)
                .frame(width: 40, alignment: .leading)
            Canvas { context, size in
                var collector = QLFCollector()
                let cells = max(1, Int(size.width / QLFLattice.cellSize))
                let occupancy = QLFLattice.barOccupancy(
                    value: min(1, Double(magnitude) / 18), cells: cells)
                for (index, value) in occupancy.enumerated() {
                    for row in 0..<3 {
                        collector.addCell(column: cells - 1 - index, row: row,
                                          occupancy: value, tier: .tier80)
                    }
                }
                collector.fill(into: context)
            }
            .frame(height: 12)
            .background(Color.eqG00)
            Text(grReadout)
                .font(.eqT0)
                .foregroundStyle(Color.eqG80)
                .frame(width: 64, alignment: .trailing)
        }
    }

    private var grReadout: String {
        let gr = meterStore.limiterGainReductionDB
        guard gr.count >= 2 else { return "0.0" }
        if isStereo {
            return String(format: "−%.1f/−%.1f", gr[0], gr[1])
        }
        return gr[0] > 0.05 ? String(format: "−%.1f", gr[0]) : "0.0"
    }
}
