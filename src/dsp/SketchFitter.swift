// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// C1: fits ordinary EQ bands to a hand-drawn target curve.
///
/// The stroke arrives as (frequency, dB) samples and is resampled
/// onto a fixed log grid; grid points the stroke never covered
/// carry no target, so a sketch of the bass region alone fits the
/// bass region alone. Edge plateaus become the house shelves
/// first (105 Hz / 10 kHz, Q 0.7 — the same shelves every import
/// path speaks); the remaining deviation is fitted greedily with
/// peaking bands whose Q comes from the deviation's half-gain
/// width. Responses are evaluated with the analog prototype, so
/// the fit is sample-rate independent.
///
/// The proposal reports its own worst residual: the UI states the
/// fit error rather than implying the sketch was matched exactly,
/// and nothing is applied until the user accepts the bands.
enum SketchFitter {
    struct Proposal {
        var bands: [EQBandConfiguration]
        /// Worst |target − fitted| across covered grid points, dB.
        var maxErrorDB: Double
    }

    static let gridCount = 97
    static let minFrequency = 20.0
    static let maxFrequency = 20_000.0
    /// Deviations smaller than this are not worth a band.
    static let stopThresholdDB = 0.75

    static func fit(
        samples: [(frequency: Double, db: Double)],
        maxBands: Int = 6
    ) -> Proposal {
        guard samples.count >= 2 else {
            return Proposal(bands: [], maxErrorDB: 0)
        }
        let sorted = samples.sorted { $0.frequency < $1.frequency }
        let grid = (0..<gridCount).map { i in
            minFrequency * pow(maxFrequency / minFrequency, Double(i) / Double(gridCount - 1))
        }
        // Target per grid point; nil where the stroke never went.
        var residual: [Double?] = grid.map { frequency in
            guard frequency >= sorted.first!.frequency, frequency <= sorted.last!.frequency else {
                return nil
            }
            return interpolatedDB(at: frequency, in: sorted)
        }

        var bands: [EQBandConfiguration] = []

        func subtract(_ band: EQBandConfiguration) {
            for i in grid.indices where residual[i] != nil {
                residual[i]! -= SVFMath.analogMagnitudeDB(
                    type: band.filterType,
                    frequency: Double(band.frequency),
                    q: Double(band.q),
                    gain: Double(band.gain),
                    at: grid[i]
                )
            }
        }

        // 1. Edge shelves: a covered plateau at either edge.
        if let shelf = edgeShelf(residual: residual, grid: grid, low: true) {
            bands.append(shelf)
            subtract(shelf)
        }
        if bands.count < maxBands, let shelf = edgeShelf(residual: residual, grid: grid, low: false) {
            bands.append(shelf)
            subtract(shelf)
        }

        // 2. Greedy peaks on the remaining deviation.
        while bands.count < maxBands {
            var worstIndex: Int? = nil
            var worstValue = 0.0
            for i in grid.indices {
                guard let value = residual[i], abs(value) > abs(worstValue) else { continue }
                worstValue = value
                worstIndex = i
            }
            guard let peak = worstIndex, abs(worstValue) >= stopThresholdDB else { break }

            let q = estimatedQ(residual: residual, grid: grid, peakIndex: peak, peakValue: worstValue)
            let band = EQBandConfiguration(
                frequency: Float(grid[peak]),
                q: Float(q),
                gain: Float(max(-18.0, min(18.0, worstValue))),
                filterType: .parametric,
                bypass: false
            )
            bands.append(band)
            subtract(band)
        }

        bands.sort { $0.frequency < $1.frequency }
        let maxError = residual.compactMap { $0.map(abs) }.max() ?? 0
        return Proposal(bands: bands, maxErrorDB: maxError)
    }

    // MARK: - Pieces

    private static func interpolatedDB(
        at frequency: Double,
        in samples: [(frequency: Double, db: Double)]
    ) -> Double {
        if frequency <= samples.first!.frequency { return samples.first!.db }
        if frequency >= samples.last!.frequency { return samples.last!.db }
        var upper = 1
        while samples[upper].frequency < frequency { upper += 1 }
        let a = samples[upper - 1], b = samples[upper]
        guard b.frequency > a.frequency else { return b.db }
        let t = (log2(frequency) - log2(a.frequency)) / (log2(b.frequency) - log2(a.frequency))
        return a.db + t * (b.db - a.db)
    }

    /// A shelf when the covered edge points form a plateau:
    /// mean at least 1 dB and spread within 1.5 dB.
    private static func edgeShelf(residual: [Double?], grid: [Double], low: Bool) -> EQBandConfiguration? {
        let edgePoints: [(index: Int, value: Double)]
        if low {
            edgePoints = grid.indices.filter { grid[$0] <= 63 }.compactMap { i in
                residual[i].map { (index: i, value: $0) }
            }
            // The stroke must actually reach the edge octave.
            guard edgePoints.count >= 3, grid[edgePoints.first!.index] <= 55 else { return nil }
        } else {
            edgePoints = grid.indices.filter { grid[$0] >= 14_125 }.compactMap { i in
                residual[i].map { (index: i, value: $0) }
            }
            guard edgePoints.count >= 3, grid[edgePoints.last!.index] >= 14_000 else { return nil }
        }
        let values = edgePoints.map(\.value)
        let mean = values.reduce(0, +) / Double(values.count)
        guard abs(mean) >= 1.0 else { return nil }
        guard values.allSatisfy({ abs($0 - mean) <= 1.5 }) else { return nil }
        return EQBandConfiguration(
            frequency: low ? 105 : 10_000,
            q: 0.7,
            gain: Float(max(-15.0, min(15.0, mean))),
            filterType: low ? .lowShelf : .highShelf,
            bypass: false
        )
    }

    /// Q from the deviation's half-gain width in octaves, through
    /// the RBJ bandwidth relation Q = 1 / (2 sinh(BW · ln2 / 2)).
    private static func estimatedQ(
        residual: [Double?], grid: [Double], peakIndex: Int, peakValue: Double
    ) -> Double {
        let half = peakValue / 2
        let sameSide: (Double) -> Bool = { value in
            peakValue > 0 ? value >= half : value <= half
        }
        var left = peakIndex
        while left > 0, let value = residual[left - 1], sameSide(value) { left -= 1 }
        var right = peakIndex
        while right < grid.count - 1, let value = residual[right + 1], sameSide(value) { right += 1 }
        // At least one grid step each side so the width is real.
        let leftFreq = grid[max(0, left - 1)]
        let rightFreq = grid[min(grid.count - 1, right + 1)]
        let widthOctaves = max(0.1, log2(rightFreq / leftFreq))
        let q = 1.0 / (2.0 * sinh(widthOctaves * log(2.0) / 2.0))
        return max(0.5, min(8.0, q))
    }
}
