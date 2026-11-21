// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// The Quantised Lattice Field: continuous acoustic values rendered
/// as dot density on a fixed 4 pt grid — the one expressive device
/// of Design System v2, re-derived from ordered-dithering and
/// dot-matrix techniques. Each 4×4 pt macro-cell holds a 2×2
/// sub-cell matrix; a sub-cell lights when the cell's occupancy
/// reaches its Bayer threshold, giving five densities per cell and,
/// across the two ink tiers an instrument uses, nine steps — with
/// no alpha blending anywhere.
///
/// This file is the pure core (occupancy maths and rect geometry,
/// unit-tested) plus the batched rect collector the Canvas views
/// fill from. Per-dot draw calls never happen: rects are collected
/// per tier and filled as four paths.
enum QLFLattice {
    /// Macro-cell pitch in points (1 u).
    static let cellSize: CGFloat = 4
    /// Lit sub-dot size in points (0.5 pt gutter preserved).
    static let dotSize: CGFloat = 1.5
    /// Sub-cell inset in points.
    static let dotInset: CGFloat = 0.25

    /// Normalised 2×2 Bayer thresholds, indexed [row][column].
    static let bayer: [[Double]] = [
        [0.125, 0.625],
        [0.875, 0.375]
    ]

    /// How many of the four sub-dots an occupancy lights (0...4).
    static func litCount(occupancy: Double) -> Int {
        let clamped = min(1, max(0, occupancy))
        var count = 0
        for row in bayer {
            for threshold in row where clamped >= threshold {
                count += 1
            }
        }
        return count
    }

    /// The lit sub-dot rects for one macro-cell at `origin`, in
    /// threshold order (top-left, bottom-right, top-right,
    /// bottom-left) so partial densities grow diagonally.
    static func litRects(occupancy: Double, origin: CGPoint) -> [CGRect] {
        var rects: [CGRect] = []
        rects.reserveCapacity(4)
        forEachLitRect(occupancy: occupancy, origin: origin) { rects.append($0) }
        return rects
    }

    /// Fixed Bayer order; the rendering hot path needs no temporary arrays or sorting.
    static func forEachLitRect(occupancy: Double, origin: CGPoint, _ body: (CGRect) -> Void) {
        for (threshold, x, y) in dots where occupancy >= threshold {
            body(CGRect(x: origin.x + x, y: origin.y + y, width: dotSize, height: dotSize))
        }
    }

    private static let dots: [(Double, CGFloat, CGFloat)] = [
        (0.125, dotInset, dotInset), (0.375, 2 + dotInset, 2 + dotInset),
        (0.625, 2 + dotInset, dotInset), (0.875, dotInset, 2 + dotInset)
    ]

    /// Occupancy per cell for a bar of `cells` cells at normalised
    /// value 0...1: full cells before the frontier, the fraction in
    /// the frontier cell, nothing after.
    static func barOccupancy(value: Double, cells: Int) -> [Double] {
        guard cells > 0 else { return [] }
        let position = min(1, max(0, value)) * Double(cells)
        return (0..<cells).map { index in
            let cellStart = Double(index)
            if position >= cellStart + 1 { return 1 }
            if position <= cellStart { return 0 }
            return position - cellStart
        }
    }

    /// A dB value normalised to 0...1 over [floorDB, 0].
    static func normalised(db: Double, floorDB: Double = -60) -> Double {
        min(1, max(0, (db - floorDB) / (0 - floorDB)))
    }
}

/// Ink tiers for lattice rendering, darkest to brightest.
enum QLFTier: Hashable {
    case tier20
    case tier35
    case tier60
    case tier80
    case tier95

    var color: Color {
        switch self {
        case .tier20: return .eqG20
        case .tier35: return .eqG35
        case .tier60: return .eqG60
        case .tier80: return .eqG80
        case .tier95: return .eqG95
        }
    }
}

/// Collects lit rects per tier for one canvas frame, then fills
/// each tier as a single path.
struct QLFCollector {
    private var paths: [QLFTier: CGMutablePath] = [:]

    mutating func addCell(column: Int, row: Int, occupancy: Double, tier: QLFTier) {
        guard occupancy > 0 else { return }
        let origin = CGPoint(
            x: CGFloat(column) * QLFLattice.cellSize,
            y: CGFloat(row) * QLFLattice.cellSize
        )
        let path: CGMutablePath
        if let existing = paths[tier] { path = existing }
        else { path = CGMutablePath(); paths[tier] = path }
        QLFLattice.forEachLitRect(occupancy: occupancy, origin: origin) { path.addRect($0) }
    }

    func fill(into context: GraphicsContext) {
        // Fixed order, darkest first, so brighter tiers always land
        // on top where cells overlap (peak over body, crest over fill).
        for tier in [QLFTier.tier20, .tier35, .tier60, .tier80, .tier95] {
            guard let tierPath = paths[tier] else { continue }
            let path = Path(tierPath)
            context.fill(path, with: .color(tier.color))
        }
    }
}
