// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// The composite EQ response behind the band stage, rendered as a
/// Quantised Lattice Field: the exact composite transfer function
/// of the edited channel (the same evaluation the auto-preamp
/// trusts, via HeadroomAnalyzer) as a chalk spine on the 4 pt
/// lattice, a quarter-density skirt between the centreline and the
/// spine, and the auto-preamp ceiling as a dotted reserved band
/// closed by a stitch line at the exact ceiling height.
///
/// Display note: coefficients are designed at the display stager's
/// 48 kHz unless the pipeline has set its rate; the shape is exact
/// at 48 kHz and deviates only near Nyquist at other rates. The
/// gain axis (±18 dB) is inset 7 pt top and bottom so the Zone D
/// rail labels align with the plot exactly.
struct CompositeCurveCanvas: View {
    @EnvironmentObject var store: EqumaczerStore

    /// Shared with the C1 sketch layer, which must map points
    /// through the exact geometry the curve is drawn with.
    static let displayRangeDB: Double = 18
    static let minFrequency: Double = 20
    static let maxFrequency: Double = 20000
    /// Vertical inset of the plot area, shared with the dB rail.
    static let plotInset: CGFloat = 7

    var body: some View {
        Canvas { context, size in
            drawCentreline(context: context, size: size)
            if store.autoPreampEnabled,
               store.eqConfiguration.autoPreampDB + store.eqConfiguration.correctionPreampDB < -0.05 {
                drawCeiling(context: context, size: size)
            }
            drawCurve(context: context, size: size)
        }
    }

    // MARK: - Geometry

    private func x(for frequency: Double, width: CGFloat) -> CGFloat {
        let t = log2(frequency / Self.minFrequency) / log2(Self.maxFrequency / Self.minFrequency)
        return CGFloat(t) * width
    }

    private func y(for db: Double, height: CGFloat) -> CGFloat {
        let clamped = max(-Self.displayRangeDB, min(Self.displayRangeDB, db))
        let plotHeight = height - Self.plotInset * 2
        return Self.plotInset + (0.5 - CGFloat(clamped / Self.displayRangeDB) * 0.5) * plotHeight
    }

    // MARK: - Drawing

    private func drawCentreline(context: GraphicsContext, size: CGSize) {
        var line = Path()
        line.move(to: CGPoint(x: 0, y: y(for: 0, height: size.height)))
        line.addLine(to: CGPoint(x: size.width, y: y(for: 0, height: size.height)))
        context.stroke(line, with: .color(.eqG20), lineWidth: 1)
    }

    /// The headroom the cascade preamp reserves: a quarter-density
    /// dotted band from the top of the plot down to the ceiling,
    /// closed by a chalk stitch at the ceiling's exact height and
    /// tagged with the total cut. The reserved band is the sum of
    /// the manual and correction cuts — the unified cascade figure.
    private func drawCeiling(context: GraphicsContext, size: CGSize) {
        let cut = Double(store.eqConfiguration.autoPreampDB + store.eqConfiguration.correctionPreampDB)
        let ceilingY = y(for: Self.displayRangeDB + cut, height: size.height)

        var dotY: CGFloat = 2
        var rowIndex = 0
        while dotY < ceilingY - 2 {
            var dotX: CGFloat = rowIndex % 2 == 0 ? 2 : 6
            while dotX < size.width {
                let rect = CGRect(x: dotX, y: dotY, width: 1.5, height: 1.5)
                context.fill(Path(rect), with: .color(.eqG35))
                dotX += 8
            }
            dotY += 8
            rowIndex += 1
        }

        var dashX: CGFloat = 0
        while dashX < size.width {
            let rect = CGRect(x: dashX, y: ceilingY - 1, width: 6, height: 2)
            context.fill(Path(rect), with: .color(.eqG95))
            dashX += 10
        }


    }

    /// The curve as a lattice spine: per 4 pt column, the composite
    /// at the column's centre frequency, split across the two
    /// nearest rows by its sub-row fraction; slope bridges where the
    /// spine jumps more than a row between columns; the area between
    /// the centreline and the spine at quarter density.
    private func drawCurve(context: GraphicsContext, size: CGSize) {
        let configuration = store.eqConfiguration
        let bands = configuration.bands
        let count = store.bandCount
        guard count > 0, bands.count >= count, size.width > 8 else { return }

        let stager = store.routingCoordinator.eqStager
        let coefficients = stager.designedCoefficients(for: bands, count: count)
        let bypassFlags = bands.map(\.bypass)

        let columns = Int(size.width / QLFLattice.cellSize)
        let rows = Int(size.height / QLFLattice.cellSize)
        let centreRow = Double(y(for: 0, height: size.height)) / Double(QLFLattice.cellSize)
        var collector = QLFCollector()
        var previousRow: Double? = nil

        for column in 0..<columns {
            let centreX = (Double(column) + 0.5) * Double(QLFLattice.cellSize)
            let t = centreX / Double(size.width)
            let frequency = Self.minFrequency * pow(Self.maxFrequency / Self.minFrequency, t)
            let db = HeadroomAnalyzer.compositeGainDB(
                svfCoefficients: coefficients,
                bypassFlags: bypassFlags,
                activeBandCount: count,
                sampleRate: stager.sampleRate,
                at: frequency
            )
            let rowPosition = Double(y(for: db, height: size.height)) / Double(QLFLattice.cellSize)

            // Skirt: rows strictly between centreline and spine.
            let skirtFirst = Int(min(centreRow, rowPosition).rounded(.up))
            let skirtLast = Int(max(centreRow, rowPosition).rounded(.down))
            if skirtLast > skirtFirst {
                for row in skirtFirst..<skirtLast where row >= 0 && row < rows {
                    collector.addCell(column: column, row: row, occupancy: 0.25, tier: .tier35)
                }
            }

            // Bridge: fill the jump from the previous column's spine.
            if let previous = previousRow, abs(rowPosition - previous) > 1 {
                var bridgeRow = Int(min(previous, rowPosition).rounded(.up)) + 1
                while Double(bridgeRow) < max(previous, rowPosition) {
                    if bridgeRow >= 0, bridgeRow < rows {
                        collector.addCell(column: column, row: bridgeRow, occupancy: 0.5, tier: .tier95)
                    }
                    bridgeRow += 1
                }
            }

            // Spine: split across the two nearest rows.
            let baseRow = Int(floor(rowPosition))
            let fraction = rowPosition - Double(baseRow)
            if baseRow >= 0, baseRow < rows {
                collector.addCell(column: column, row: baseRow, occupancy: 1 - fraction, tier: .tier95)
            }
            if fraction > 0.05, baseRow + 1 >= 0, baseRow + 1 < rows {
                collector.addCell(column: column, row: baseRow + 1, occupancy: fraction, tier: .tier95)
            }
            previousRow = rowPosition
        }
        collector.fill(into: context)
    }
}
