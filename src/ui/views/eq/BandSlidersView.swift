import SwiftUI

/// All ordinary bands fit together; dense 32–64 band curves use explicit pages.
struct BandSlidersView: View {
    @EnvironmentObject private var store: EqumaczerStore
    @State private var page = 0
    @State private var selectedBand = 0
    @State private var inputSelected = false

    var body: some View {
        GeometryReader { geometry in
            let perPage = store.bandCount < 32 ? max(1, store.bandCount) : max(1, Int((geometry.size.width - 96) / 40))
            let pages = max(1, (store.bandCount + perPage - 1) / perPage)
            let current = min(page, pages - 1)
            let start = current * perPage
            let end = min(store.bandCount, start + perPage)
            VStack(spacing: 4) {
                if pages > 1 {
                    HStack {
                        Button("Prev") { page = max(0, current - 1) }.disabled(current == 0)
                        Spacer()
                        Text("\(start + 1)–\(end) of \(store.bandCount)")
                        Spacer()
                        Button("Next") { page = min(pages - 1, current + 1) }.disabled(current == pages - 1)
                    }.font(.eqT0).buttonStyle(.plain)
                }
                HStack(spacing: 4) {
                    ForEach(start..<end, id: \.self) { index in
                        EQBandSliderView(index: index, band: store.eqConfiguration.bands[index],
                            gain: Binding(get: { store.eqConfiguration.bands[index].gain }, set: { store.updateBandGain(index: index, gain: $0) }),
                            frequencyUpdate: { value in change(index, label: "frequency") { store.updateBandFrequency(index: index, frequency: AudioConstants.clampFrequency(value)) } },
                            qUpdate: { value in change(index, label: "Q") { store.updateBandQ(index: index, q: BandwidthConverter.clampQ(value)) } },
                            filterTypeUpdate: { value in change(index, label: "type") { store.updateBandFilterType(index: index, filterType: value) } },
                            bypassUpdate: { value in change(index, label: "bypass") { store.updateBandBypass(index: index, bypass: value) } },
                            compact: true,
                            compactGainWidth: min(34, max(12, (geometry.size.width - 96) / CGFloat(max(1, end - start)) - 6)),
                            onSelect: { selectedBand = index; inputSelected = false })
                    }
                    Divider()
                    master("in", gain: store.inputGain, update: store.updateInputGain) { inputSelected = true }
                    master("out", gain: store.outputGain, update: store.updateOutputGain) { inputSelected = false; selectedBand = -1 }
                }
                inspector
            }
        }
    }

    private func change(_ index: Int, label: String, _ action: () -> Void) {
        let before = store.captureSoundState()
        action()
        store.registerSoundUndo(label: "Band \(index + 1) \(label)", state: before)
    }

    private func master(_ name: String, gain: Float, update: @escaping (Float) -> Void, select: @escaping () -> Void) -> some View {
        EQBandSliderView(index: -1, band: .parametric(frequency: 1000),
            gain: Binding(get: { gain }, set: { update($0) }), frequencyUpdate: { _ in }, qUpdate: { _ in },
            filterTypeUpdate: { _ in }, bypassUpdate: { _ in }, compact: true, title: name, onSelect: select)
            .frame(width: 38)
    }

    @ViewBuilder private var inspector: some View {
        HStack(spacing: 10) {
            if inputSelected {
                Toggle("Auto headroom", isOn: Binding(get: { store.autoPreampEnabled }, set: { store.autoPreampEnabled = $0 }))
                    .toggleStyle(.switch).controlSize(.mini).fixedSize()
                Text(String(format: "CUT %.1f · CORR %.1f · TOTAL %.1f dB", store.eqConfiguration.autoPreampDB, store.eqConfiguration.correctionPreampDB, store.eqConfiguration.autoPreampDB + store.eqConfiguration.correctionPreampDB))
            } else if selectedBand >= 0 && selectedBand < store.bandCount {
                let band = store.eqConfiguration.bands[selectedBand]
                Text(String(format: "%.0f Hz", band.frequency))
                Text(band.filterType.displayName)
                Text(String(format: "Q %.2f", band.q))
                Text(String(format: "%+.1f dB", band.gain))
                if band.bypass { Text("bypassed") }
            } else { Text("Output gain") }
            Spacer(minLength: 0)
        }.font(.eqT0).foregroundStyle(Color.eqG60).frame(height: 20)
    }
}
