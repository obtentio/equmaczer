// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// Clay: the existing curve and sketch editor with axes inside the well.
struct ClayStageView: View {
    @EnvironmentObject var store: EqumaczerStore
    // C1: sketch-to-bands state.
    @Binding var sketchArmed: Bool
    @State private var strokePoints: [CGPoint] = []
    @State private var sketchProposal: SketchFitter.Proposal? = nil
    @State private var dragBand: Int?
    @State private var dragGain: Float = 0
    @State private var dragFrequency: Float = 1000
    @State private var dragBaseline: SoundState?

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) { dbRail; stage }
                .padding(.bottom, 20)
            HStack(spacing: 0) { Color.clear.frame(width: 48); frequencyStrip }.frame(height: 20)
                .allowsHitTesting(false)
        }
        .background(Color.eqG00)
        .onChange(of: sketchArmed) { _, _ in strokePoints = []; sketchProposal = nil }
    }

    private var stage: some View {
        ZStack {
            ResponsePlotView()
            if !sketchArmed {
                GeometryReader { geo in
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                if dragBand == nil {
                                    let t = max(0, min(1, (value.startLocation.x - 12) / max(1, geo.size.width - 24)))
                                    let frequency = 20 * pow(1000, Double(t))
                                    let bands = store.eqConfiguration.bands.prefix(store.bandCount)
                                    dragBand = bands.indices.filter { !bands[$0].bypass }.min {
                                        abs(log(Double(bands[$0].frequency) / frequency)) < abs(log(Double(bands[$1].frequency) / frequency))
                                    }
                                    if let index = dragBand {
                                        dragGain = store.eqConfiguration.bands[index].gain
                                        dragFrequency = store.eqConfiguration.bands[index].frequency
                                        dragBaseline = store.captureSoundState()
                                    }
                                }
                                if let index = dragBand {
                                    let delta = Float(-value.translation.height / max(1, geo.size.height - 14) * 36)
                                    let factor = pow(1000, Double(value.translation.width / max(1, geo.size.width - 24)))
                                    store.updateBandShape(index: index, frequency: dragFrequency * Float(factor), gain: dragGain + delta)
                                }
                            }
                            .onEnded { _ in
                                if let baseline = dragBaseline { store.registerSoundUndo(label: "Shape curve", state: baseline) }
                                dragBand = nil; dragBaseline = nil
                            })
                        .accessibilityLabel("Drag the curve horizontally for frequency and vertically for gain; use Bands for precise values")
                }
            }

            if sketchArmed {
                sketchLayer
            }

            if let proposal = sketchProposal {
                proposalBar(proposal)
            }
        }
    }

    // MARK: - C1 sketch layer

    /// The drawing surface shown while sketching: the stroke in
    /// chalk over the live curve, mapped through the curve
    /// canvas's own geometry (12 pt stage padding, plot inset,
    /// log frequency, ±18 dB).
    private var sketchLayer: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { context, _ in
                    guard strokePoints.count > 1 else { return }
                    var path = Path()
                    path.move(to: strokePoints[0])
                    for point in strokePoints.dropFirst() { path.addLine(to: point) }
                    context.stroke(path, with: .color(.eqG95), lineWidth: 2)
                }
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if let last = strokePoints.last,
                                   hypot(value.location.x - last.x, value.location.y - last.y) < 2 { return }
                                strokePoints.append(value.location)
                            }
                            .onEnded { _ in fitStroke(size: geo.size) }
                    )
                if strokePoints.isEmpty {
                    Text("Draw the curve you want — release to fit bands")
                        .font(.eqT1)
                        .foregroundStyle(Color.eqG60)
                        .position(x: geo.size.width / 2, y: 18)
                }
            }
        }
    }

    private func fitStroke(size: CGSize) {
        let plotWidth = Double(size.width) - 24
        let plotHeight = Double(size.height) - Double(CompositeCurveCanvas.plotInset) * 2
        guard plotWidth > 8, plotHeight > 8, strokePoints.count > 1 else { return }
        let samples: [(frequency: Double, db: Double)] = strokePoints.map { point in
            let t = max(0, min(1, (Double(point.x) - 12) / plotWidth))
            let frequency = CompositeCurveCanvas.minFrequency
                * pow(CompositeCurveCanvas.maxFrequency / CompositeCurveCanvas.minFrequency, t)
            let dbT = (Double(point.y) - Double(CompositeCurveCanvas.plotInset)) / plotHeight
            let db = max(-18, min(18, (0.5 - dbT) * 2 * CompositeCurveCanvas.displayRangeDB))
            return (frequency: frequency, db: db)
        }
        sketchProposal = SketchFitter.fit(samples: samples)
    }

    /// The fitted bands are a proposal, never an ambush: count,
    /// honest fit error, and an explicit Use before anything is
    /// applied — through the same store path presets use, so the
    /// bands land as ordinary editable objects.
    private func proposalBar(_ proposal: SketchFitter.Proposal) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                if proposal.bands.isEmpty {
                    Text("That sketch is flat — no bands to add")
                        .font(.eqT1)
                        .foregroundStyle(Color.eqG80)
                } else {
                    Text("\(proposal.bands.count) band\(proposal.bands.count == 1 ? "" : "s") · fits within \(String(format: "%.1f", proposal.maxErrorDB)) dB")
                        .font(.eqT1)
                        .foregroundStyle(Color.eqG80)
                    Button {
                        commitSketch(proposal)
                    } label: {
                        Text("Use bands").font(.eqT1).foregroundStyle(Color.eqG95)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    sketchProposal = nil
                    strokePoints = []
                } label: {
                    Text("Discard").font(.eqT1).foregroundStyle(Color.eqG60)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.eqG10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func commitSketch(_ proposal: SketchFitter.Proposal) {
        store.performSoundChange(label: "Use sketch") { config in
            config.setActiveBandCount(proposal.bands.count)
            for (index, band) in proposal.bands.enumerated() {
                config.updateBandFrequency(index: index, frequency: AudioConstants.clampFrequency(band.frequency))
                config.updateBandQ(index: index, q: BandwidthConverter.clampQ(band.q))
                config.updateBandGain(index: index, gain: band.gain)
                config.updateBandFilterType(index: index, filterType: band.filterType)
                config.updateBandBypass(index: index, bypass: false)
            }
        }
        sketchProposal = nil
        strokePoints = []
        sketchArmed = false
    }

    /// The gain axis, sharing the curve canvas's inset mapping:
    /// +18 / +9 / 0 / −9 / −18 down the plot's height.
    private var dbRail: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach([(18.0, "+18"), (9.0, "+9"), (0.0, "0"), (-9.0, "−9"), (-18.0, "−18")], id: \.0) { db, label in
                    Text(label)
                        .font(.eqT0)
                        .foregroundStyle(db == 0 ? Color.eqG80 : Color.eqG60)
                        .frame(width: 40, alignment: .trailing)
                        .position(
                            x: 22,
                            y: CompositeCurveCanvas.plotInset
                                + (0.5 - CGFloat(db) / 36) * (geo.size.height - CompositeCurveCanvas.plotInset * 2)
                        )
                }
            }
        }
        .frame(width: 48)
    }

    /// Log frequency ticks and labels under the stage, on the same
    /// horizontal axis as the canvases (12 pt stage padding).
    private var frequencyStrip: some View {
        Canvas { context, size in
            let marks: [(Double, String)] = [
                (20, "20"), (50, "50"), (100, "100"), (200, "200"), (500, "500"),
                (1000, "1K"), (2000, "2K"), (5000, "5K"), (10000, "10K"), (20000, "20K")
            ]
            for (frequency, label) in marks {
                let t = log2(frequency / 20) / log2(1000.0)
                let x = CGFloat(t) * size.width
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: 0))
                tick.addLine(to: CGPoint(x: x, y: 4))
                context.stroke(tick, with: .color(.eqG20), lineWidth: 1)
                let anchor: UnitPoint = x < 10 ? .topLeading : (x > size.width - 16 ? .topTrailing : .top)
                context.draw(
                    Text(label).font(.eqT0).foregroundColor(.eqG60),
                    at: CGPoint(x: x, y: 6),
                    anchor: anchor
                )
            }
        }
        .frame(height: 20)
        .padding(.horizontal, 12)
    }
}
