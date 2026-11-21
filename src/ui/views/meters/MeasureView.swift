import SwiftUI

struct MeasureView: View {
    @ObservedObject var store: EqumaczerStore
    @ObservedObject private var meters: MeterStore
    @ObservedObject private var dose: DoseController
    let checkController: TranslationCheckController?
    let compact: Bool
    @State private var showBlind = false

    init(store: EqumaczerStore, checkController: TranslationCheckController?, compact: Bool) {
        self.store = store
        self.meters = store.meterStore
        self.dose = store.doseController
        self.checkController = checkController
        self.compact = compact
    }

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 10) {
                    meterBars.frame(width: 65, height: 20)
                    Text("\(peak) dB")
                    Text("\(number(meters.integratedLUFS)) LUFS")
                    Text("\(number(meters.shortTermLUFS)) short")
                    Text("dose today \(dosePercent)%")
                    Spacer(minLength: 0)
                    listenControls
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("Measure").font(.eqT2Medium); Text("live").foregroundStyle(Color.eqG60) }
                    meterBars.frame(maxHeight: .infinity)
                    reading(peak, "dB out peak")
                    reading(number(meters.integratedLUFS), "LUFS integrated")
                    reading(number(meters.shortTermLUFS), "LUFS short-term")
                    Text("dose today \(dosePercent)%").help("Estimated exposure, relative to the weekly reference budget; not a sound-level measurement")
                    Divider()
                    HStack { Text("Listen"); Spacer(); Text(meters.bypassMatchDB.map { String(format: "%+.1f dB", $0) } ?? "level-matched").foregroundStyle(Color.eqG60) }
                    listenControls
                }
            }
        }
        .font(.eqT0).monospacedDigit()
        .padding(10).background(Color.eqG10)
        .sheet(isPresented: $showBlind) { BlindABView(store: store, correctionController: store.correctionController, mode: .preset) }
    }

    @ViewBuilder private var listenControls: some View {
        if compact {
            HStack(spacing: 6) { compare; check; blind }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) { compare; check }
                blind
            }
        }
    }
    private var compare: some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                compareButton("EQ", mode: .eq)
                compareButton("Flat", mode: .flat)
            }.overlay(Rectangle().stroke(Color.eqG20, lineWidth: 1))
            if compact, let delta = meters.bypassMatchDB { Text(String(format: "%+.1f dB", delta)).font(.eqT0) }

        }.help("Compare EQ/Flat at matched loudness. Automatically returns to EQ after five minutes.")
    }
    private func compareButton(_ label: String, mode: CompareMode) -> some View {
        Button { store.compareMode = mode } label: {
            Text(label).frame(width: 38, height: 22)
                .foregroundStyle(store.compareMode == mode ? Color.eqG00 : Color.eqG80)
                .background(store.compareMode == mode ? Color.eqG80 : Color.clear)
        }.buttonStyle(.plain).accessibilityLabel("Compare \(label)")
    }
    @ViewBuilder private var check: some View {
        if let checkController { TranslationCheckMenu(store: store, controller: checkController) }
    }
    private var blind: some View { Button("Blind test") { showBlind = true }.buttonStyle(.bordered).controlSize(.small) }
    private var peak: String { String(format: "%.1f", max(meters.peakReadoutsDB[2], meters.peakReadoutsDB[3])) }
    private var dosePercent: Int { Int(((dose.week.last?.fraction ?? 0) * 100).rounded()) }
    private func number(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "—" }
    private func reading(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(value).font(.eqT3); Text(label).foregroundStyle(Color.eqG60) }
    }
    private var meterBars: some View {
        HStack(spacing: compact ? 2 : 8) {
            if !compact {
                VStack {
                    ForEach(["0", "−12", "−24", "−36"], id: \.self) { label in
                        Text(label).font(.system(size: 9))
                        if label != "−36" { Spacer() }
                    }
                }.foregroundStyle(Color.eqG60).padding(.bottom, 14)
            }
            ForEach(0..<5) { index in
                VStack(spacing: 3) {
                    Canvas { context, size in
                        let enabled = meters.metersEnabled
                        let position = index < 4 ? (enabled ? meters.peakPositions[index] : 0) : min(1, (meters.limiterGainReductionDB.max() ?? 0) / 18)
                        let rms = index < 4 ? (enabled ? meters.rmsPositions[index] : 0) : position
                        let hold = index < 4 ? (enabled ? meters.peakHoldPositions[index] : 0) : 0
                        for y in stride(from: CGFloat(0), to: size.height, by: 3) {
                            let level = 1 - y / max(1, size.height)
                            if level <= CGFloat(position) {
                                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 2)), with: .color(level <= CGFloat(rms) ? .eqG80 : .eqG60))
                            }
                        }
                        if hold > 0 { context.fill(Path(CGRect(x: 0, y: (1 - CGFloat(hold)) * size.height, width: size.width, height: 2)), with: .color(.eqG95)) }
                    }.background(Color.eqG00).frame(maxWidth: index == 4 ? 5 : 14)
                    if !compact { Text(["IN L", "IN R", "OUT L", "OUT R", "LIM"][index]).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.7) }
                }
            }
        }
        .accessibilityLabel("Input and output stereo meters and limiter gain reduction")
    }
}
