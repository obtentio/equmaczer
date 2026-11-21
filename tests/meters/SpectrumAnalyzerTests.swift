// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// The live output spectrum: a sine peaks in its own log band at
/// roughly its true level; silence stays at the floor.
final class SpectrumAnalyzerTests: XCTestCase {

    private func feed(_ analyzer: SpectrumAnalyzer, _ signal: [Float], repeats: Int = 3) {
        for _ in 0..<repeats {
            signal.withUnsafeBufferPointer { ptr in
                analyzer.feed(buffers: [ptr.baseAddress!], frameCount: ptr.count)
            }
        }
    }

    private func settledBands(_ analyzer: SpectrumAnalyzer) -> [Float] {
        var bands: [Float] = []
        for _ in 0..<8 { bands = analyzer.computeBands() }
        return bands
    }

    private func sine(frequency: Double, amplitude: Float, frames: Int = 8192) -> [Float] {
        (0..<frames).map { amplitude * Float(sin(2 * Double.pi * frequency * Double($0) / 48000)) }
    }

    func testSilenceStaysAtTheFloor() {
        let analyzer = SpectrumAnalyzer()
        feed(analyzer, [Float](repeating: 0, count: 8192))
        let bands = settledBands(analyzer)
        XCTAssertEqual(bands.count, SpectrumAnalyzer.bandCount)
        XCTAssertTrue(bands.allSatisfy { $0 <= -85 }, "silence must read at the floor, got \(bands.max() ?? 0)")
    }

    func testOneKilohertzSinePeaksInItsBand() {
        let analyzer = SpectrumAnalyzer()
        feed(analyzer, sine(frequency: 1000, amplitude: 0.5))
        let bands = settledBands(analyzer)

        let peakIndex = bands.enumerated().max { $0.element < $1.element }!.offset
        // Band 27 spans ~943–1085 Hz on the 20 Hz–20 kHz log axis.
        XCTAssertEqual(peakIndex, 27, "1 kHz must peak in band 27, peaked in \(peakIndex)")
        XCTAssertEqual(bands[peakIndex], -6, accuracy: 2.5, "a 0.5-amplitude sine reads ≈ −6 dBFS")
        XCTAssertLessThan(bands[5], -40, "no energy should leak into the low bands")
    }

    func testBassSinePeaksBelowTrebleSine() {
        let bass = SpectrumAnalyzer()
        feed(bass, sine(frequency: 100, amplitude: 0.5))
        let bassPeak = settledBands(bass).enumerated().max { $0.element < $1.element }!.offset

        let treble = SpectrumAnalyzer()
        feed(treble, sine(frequency: 8000, amplitude: 0.5))
        let treblePeak = settledBands(treble).enumerated().max { $0.element < $1.element }!.offset

        XCTAssertLessThan(bassPeak, treblePeak)
        XCTAssertEqual(bassPeak, 11, accuracy: 1, "100 Hz peaks near band 11")
    }
}
