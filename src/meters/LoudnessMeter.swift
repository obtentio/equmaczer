// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// Control-thread loudness maths over block energies drained from
/// `LoudnessProbe`s: BS.1770-4 gated integrated loudness, short-term
/// and momentary loudness, and the pre/post-EQ loudness delta that
/// drives loudness-matched bypass.
///
/// Gating follows BS.1770-4: an absolute gate at −70 LUFS, then a
/// relative gate 10 LU below the ungated measurement, recomputed
/// once. The bypass delta uses paired blocks gated on programme
/// presence only (a ratio over the same material needs no relative
/// gate) and requires at least 3 seconds of gated programme before
/// it is considered real.
final class LoudnessMeter {
    private(set) var integratedLUFS: Double?
    private(set) var shortTermLUFS: Double?
    private(set) var momentaryLUFS: Double?
    /// Loudness the EQ path adds (post − pre, dB). Nil until enough
    /// gated programme has been measured.
    private(set) var bypassDeltaDB: Double?

    private var displayBlocks: [Double] = []
    private var preBlocks: [Double] = []
    private var postBlocks: [Double] = []

    /// One hour of blocks at the 100 ms hop; older blocks drop off.
    private static let maxBlocks = 36_000
    private static let absoluteGateLUFS = -70.0
    private static let deltaGateLUFS = -60.0
    private static let deltaMinimumPairs = 30

    func reset() {
        displayBlocks = []
        preBlocks = []
        postBlocks = []
        integratedLUFS = nil
        shortTermLUFS = nil
        momentaryLUFS = nil
        bypassDeltaDB = nil
    }

    /// A restage changed the EQ the paired delta describes. The
    /// paired histories are cleared — left in place, the delta
    /// becomes a decaying blend of the old and new configurations
    /// (the histories hold up to an hour of blocks). The held delta
    /// is not zeroed: it is shifted by the restage's total preamp
    /// change, which moves post-EQ loudness broadband, so the match
    /// stays within ~1 LU until fresh gated pairs refine it. With
    /// no converged delta to shift, the seed is the new total
    /// preamp itself. Display history is programme history and is
    /// kept — it measures what actually played.
    func restage(preampDeltaDB: Double, absoluteSeedDB: Double) {
        preBlocks = []
        postBlocks = []
        if let previous = bypassDeltaDB {
            bypassDeltaDB = min(12.0, max(-12.0, previous + preampDeltaDB))
        } else if absoluteSeedDB != 0 {
            bypassDeltaDB = min(12.0, max(-12.0, absoluteSeedDB))
        }
    }

    /// Appends freshly drained blocks and recomputes all readings.
    /// Pre and post blocks arrive paired (fed identical frame
    /// sequences while the EQ runs), so histories stay index-aligned.
    func ingest(display: [Double], pre: [Double], post: [Double]) {
        if !display.isEmpty {
            displayBlocks.append(contentsOf: display)
            trim(&displayBlocks)
            momentaryLUFS = Self.loudness(ofZ: displayBlocks.last ?? 0)
            shortTermLUFS = Self.loudness(ofZ: displayBlocks.suffix(30).reduce(0, +) / Double(min(30, displayBlocks.count)))
            integratedLUFS = Self.gatedIntegratedLUFS(blockZ: displayBlocks)
        }
        if !pre.isEmpty || !post.isEmpty {
            preBlocks.append(contentsOf: pre)
            postBlocks.append(contentsOf: post)
            trim(&preBlocks)
            trim(&postBlocks)
            bypassDeltaDB = Self.pairedDeltaDB(pre: preBlocks, post: postBlocks) ?? bypassDeltaDB
        }
    }

    private func trim(_ blocks: inout [Double]) {
        if blocks.count > Self.maxBlocks {
            blocks.removeFirst(blocks.count - Self.maxBlocks)
        }
    }

    // MARK: - Pure maths (tested directly)

    /// LUFS for a summed channel mean square (z), per BS.1770.
    static func loudness(ofZ z: Double) -> Double? {
        guard z > 0 else { return nil }
        return -0.691 + 10.0 * log10(z)
    }

    /// Two-pass gated integrated loudness over block energies.
    static func gatedIntegratedLUFS(blockZ: [Double]) -> Double? {
        let absoluteGated = blockZ.filter { (loudness(ofZ: $0) ?? -.infinity) > absoluteGateLUFS }
        guard !absoluteGated.isEmpty else { return nil }
        guard let ungated = loudness(ofZ: absoluteGated.reduce(0, +) / Double(absoluteGated.count)) else {
            return nil
        }
        let relativeThreshold = ungated - 10.0
        let gated = absoluteGated.filter { (loudness(ofZ: $0) ?? -.infinity) > relativeThreshold }
        guard !gated.isEmpty else { return nil }
        return loudness(ofZ: gated.reduce(0, +) / Double(gated.count))
    }

    /// Loudness difference between paired pre/post block energies.
    static func pairedDeltaDB(pre: [Double], post: [Double]) -> Double? {
        let pairCount = min(pre.count, post.count)
        var sumPre = 0.0
        var sumPost = 0.0
        var gatedPairs = 0
        for index in 0..<pairCount {
            let loudest = max(loudness(ofZ: pre[index]) ?? -.infinity, loudness(ofZ: post[index]) ?? -.infinity)
            guard loudest > deltaGateLUFS else { continue }
            sumPre += pre[index]
            sumPost += post[index]
            gatedPairs += 1
        }
        guard gatedPairs >= deltaMinimumPairs, sumPre > 0, sumPost > 0 else { return nil }
        return 10.0 * log10(sumPost / sumPre)
    }
}
