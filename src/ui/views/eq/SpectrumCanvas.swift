// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// The live output spectrum behind the band stage, rendered as a
/// Quantised Lattice Field: the analyser's 48 log-spaced bands
/// interpolated onto the 4 pt lattice columns over the same log
/// axis as the curve (20 Hz – 20 kHz). Bar bodies tier from G35
/// through G60 with a G80 crest; silence collapses to G20
/// registration pins along the baseline — never a fake floor.
struct SpectrumCanvas: View {
    let meterStore: MeterStore
    @State private var bands: [Float] = []
    @State private var layoutCache = SpectrumLayoutCache()

    var body: some View {
        GeometryReader { geometry in
            SpectrumFrameCanvas(frame: SpectrumFrame(bands: bands, size: geometry.size, samples: layoutCache.samples(size: geometry.size, bandCount: bands.count)))
                .equatable()
        }
        .onReceive(meterStore.$spectrumBands.removeDuplicates()) { bands = $0 }
    }
}

/// Size-dependent interpolation weights are reused until the layout changes.
private final class SpectrumLayoutCache {
    private var size: CGSize = .zero
    private var bandCount = -1
    private var cached: [(lower: Int, upper: Int, mix: Double)] = []

    func samples(size: CGSize, bandCount: Int) -> [(lower: Int, upper: Int, mix: Double)] {
        if self.size == size && self.bandCount == bandCount { return cached }
        self.size = size
        self.bandCount = bandCount
        cached.removeAll(keepingCapacity: true)
        let columns = max(0, Int(size.width / QLFLattice.cellSize))
        cached.reserveCapacity(columns)
        guard bandCount > 1 else { return cached }
        for column in 0..<columns {
            let position = (Double(column) + 0.5) / Double(columns) * Double(bandCount - 1)
            let lower = Int(position)
            cached.append((lower, min(lower + 1, bandCount - 1), position - Double(lower)))
        }
        return cached
    }
}

/// Compare the actual lattice cells, including the tier frontier and crest.
/// Sub-threshold analyser changes therefore never invalidate the Canvas.
struct SpectrumFrame: Equatable {
    let size: CGSize
    let levels: [Double]
    let signatures: [[Int]]
    let silent: Bool

    init(bands: [Float], size: CGSize, samples: [(lower: Int, upper: Int, mix: Double)]? = nil) {
        self.size = size
        let columns = max(0, Int(size.width / QLFLattice.cellSize))
        var levels = [Double]()
        levels.reserveCapacity(columns)
        let weights = samples ?? SpectrumLayoutCache().samples(size: size, bandCount: bands.count)
        if bands.count > 1 {
            for sample in weights {
                let db = Double(bands[sample.lower]) * (1 - sample.mix) + Double(bands[sample.upper]) * sample.mix
                levels.append(QLFLattice.normalised(db: db, floorDB: Double(SpectrumAnalyzer.floorDB)))
            }
        } else {
            levels = Array(repeating: 0, count: columns)
        }
        self.levels = levels
        silent = (levels.max() ?? 0) < 0.02
        signatures = silent ? [] : levels.map { Self.signature(height: $0 * size.height) }
    }

    static func signature(height: Double) -> [Int] {
        guard height > 1 else { return [] }
        let pitch = Double(QLFLattice.cellSize)
        let rows = Int(ceil(height / pitch))
        let top = QLFLattice.litCount(occupancy: (height - Double(rows - 1) * pitch) / pitch)
        // Number of full body cells whose centre is below the 60% frontier.
        let low = min(rows - 1, max(0, Int(ceil((height * 0.6 - pitch / 2) / pitch))))
        return [rows, top, low]
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.size == rhs.size && lhs.silent == rhs.silent && lhs.signatures == rhs.signatures
    }
}

private struct SpectrumFrameCanvas: View, Equatable {
    let frame: SpectrumFrame

    var body: some View {
        Canvas { context, size in
            guard size.width > 8, size.height > 8 else { return }
            let columns = frame.levels.count
            let rows = Int(size.height / QLFLattice.cellSize)
            let levels = frame.levels
            var collector = QLFCollector()

            guard !frame.silent else {
                for column in stride(from: 0, to: columns, by: 2) {
                    collector.addCell(column: column, row: rows - 1, occupancy: 1, tier: .tier20)
                }
                collector.fill(into: context)
                return
            }

            for column in 0..<columns {
                let levelHeight = levels[column] * Double(size.height)
                guard levelHeight > 1 else { continue }
                let occupiedRows = Int(ceil(levelHeight / Double(QLFLattice.cellSize)))
                for aboveBase in 0..<occupiedRows {
                    let cellBottom = Double(aboveBase) * Double(QLFLattice.cellSize)
                    let occupancy = min(1, (levelHeight - cellBottom) / Double(QLFLattice.cellSize))
                    let fraction = (cellBottom + 2) / levelHeight
                    // One full tier dimmer than the original
                    // G35/G60/G80 (layout pass 2): the spectrum is
                    // background data and must sit a plane behind
                    // the G95 curve spine and the band controls.
                    let tier: QLFTier = aboveBase == occupiedRows - 1
                        ? .tier60
                        : (fraction < 0.6 ? .tier20 : .tier35)
                    collector.addCell(
                        column: column,
                        row: rows - 1 - aboveBase,
                        occupancy: occupancy,
                        tier: tier
                    )
                }
            }
            collector.fill(into: context)
        }
    }

}
