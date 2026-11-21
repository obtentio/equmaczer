// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// C4: the palette's matching — single facets, the composite
/// (the card's "AirPods + Film + Night" as one action), token
/// rules, and the result cap.
final class PaletteIndexTests: XCTestCase {
    private var executed: [String] = []

    private func action(_ id: String, _ title: String, facet: PaletteAction.Facet? = nil, keywords: [String] = []) -> PaletteAction {
        PaletteAction(id: id, title: title, facet: facet, keywords: keywords) { [self] in
            executed.append(id)
        }
    }

    private func index() -> PaletteIndex {
        PaletteIndex(actions: [
            action("dev-airpods", "Output — AirPods Pro", facet: .device("AirPods Pro"), keywords: ["output"]),
            action("dev-speakers", "Output — Studio Speakers", facet: .device("Studio Speakers"), keywords: ["output"]),
            action("ch-film", "Channel — Film", facet: .channel("Film"), keywords: ["channel"]),
            action("ch-music", "Channel — Music", facet: .channel("Music"), keywords: ["channel"]),
            action("pre-night", "Preset — Night", facet: .preset("Night"), keywords: ["preset"]),
            action("pre-flat", "Preset — Flat", facet: .preset("Flat"), keywords: ["preset"]),
            action("cmd-bypass", "Bypass — On", keywords: ["bypass"]),
        ])
    }

    func testSingleFacetSearch() {
        let results = index().results(for: "night")
        XCTAssertEqual(results.first?.id, "pre-night")
    }

    func testCompositeAppliesAllThreeInOrder() {
        let results = index().results(for: "airpods film night")
        XCTAssertEqual(results.first?.id, "composite")
        results.first?.execute()
        XCTAssertEqual(executed, ["dev-airpods", "ch-film", "pre-night"])
    }

    func testCompositeWithPlusSeparators() {
        let results = index().results(for: "AirPods + Film + Night")
        XCTAssertEqual(results.first?.id, "composite")
    }

    func testTwoFacetsAlsoCompose() {
        let results = index().results(for: "speakers night")
        XCTAssertEqual(results.first?.id, "composite")
        results.first?.execute()
        XCTAssertEqual(executed, ["dev-speakers", "pre-night"])
    }

    func testUnconsumedTokenBlocksComposite() {
        // "zzz" names nothing, so the query is not a composite —
        // and no plain action matches all tokens either.
        let results = index().results(for: "airpods film zzz")
        XCTAssertTrue(results.isEmpty)
    }

    func testCommandFoundByKeyword() {
        let results = index().results(for: "byp")
        XCTAssertEqual(results.map(\.id), ["cmd-bypass"])
    }

    func testEmptyQueryShowsCatalogueCapped() {
        let results = index().results(for: "")
        XCTAssertEqual(results.count, 7)
        let big = PaletteIndex(actions: (0..<20).map { action("a\($0)", "Action \($0)") })
        XCTAssertEqual(big.results(for: "").count, 8)
    }
}
