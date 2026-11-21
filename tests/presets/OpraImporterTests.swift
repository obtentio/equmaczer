// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// A7 OPRA import. The vendor, product, and two EQ lines below are
/// verbatim from the live OPRA database (database_v1.jsonl,
/// 2026-11-16) — FiiO FH1 with presets by oratory1990 and AutoEQ.
/// One synthetic EQ line (author "Synthetic") exercises the
/// unsupported-band path; one garbage line and one EQ for an
/// unknown product exercise tolerance.
final class OpraImporterTests: XCTestCase {
    private let fixture = #"""
{"type":"vendor","id":"fiio","data":{"name":"FiiO","logo":"assets/e5/db/e5db4d229d4c922ad3162339dad11f9f650650c1b203c7487687821ce6e9e1c1.png","blurb":"FiiO Electronics Technology Co., Ltd. is a Chinese audio equipment manufacturer headquartered in Guangzhou. FiiO specializes in equipment for the consumer audio market, including digital audio players, amplifiers, and earphones."}}
{"type":"product","id":"fiio::fh1","data":{"name":"FH1","type":"headphones","subtype":"in_ear","vendor_id":"fiio","line_art_svg":"assets/35/bb/35bb6ea54a565f6d7f672c9b9a68db361863d5cef43ebbd70d9a4d333d192103.svg","line_art_96x64_png":"assets/35/bb/35bb6ea54a565f6d7f672c9b9a68db361863d5cef43ebbd70d9a4d333d192103.v1.96x64.png"}}
{"type":"eq","id":"fiio:fh1::oratory1990_usound_target","data":{"author":"oratory1990","details":"USound Target","link":"https://www.dropbox.com/s/9vpptdxbat9ywgy/Fiio%20FH1%20%28USound%20Target%29.pdf?dl=0","type":"parametric_eq","parameters":{"gain_db":-7.6,"bands":[{"type":"peak_dip","frequency":250,"gain_db":-2.3,"q":1},{"type":"peak_dip","frequency":900,"gain_db":3.9,"q":1.2},{"type":"peak_dip","frequency":1650,"gain_db":-3.5,"q":1},{"type":"peak_dip","frequency":3000,"gain_db":2.5,"q":3},{"type":"peak_dip","frequency":6100,"gain_db":8,"q":1.8},{"type":"peak_dip","frequency":8400,"gain_db":-10,"q":6},{"type":"peak_dip","frequency":13000,"gain_db":4,"q":2}]},"product_id":"fiio::fh1"}}
{"type":"eq","id":"fiio:fh1::autoeq_crinacle","data":{"author":"AutoEQ","details":"Measured by crinacle","type":"parametric_eq","parameters":{"gain_db":-6.4,"bands":[{"type":"low_shelf","frequency":105,"gain_db":-1.7,"q":0.7},{"type":"peak_dip","frequency":176,"gain_db":-4.7,"q":0.74},{"type":"peak_dip","frequency":4656,"gain_db":5.9,"q":0.74},{"type":"peak_dip","frequency":1783,"gain_db":-4.1,"q":1.31},{"type":"peak_dip","frequency":806,"gain_db":3.2,"q":1.28},{"type":"high_shelf","frequency":10000,"gain_db":-0.1,"q":0.7},{"type":"peak_dip","frequency":6170,"gain_db":2.1,"q":4.52},{"type":"peak_dip","frequency":7736,"gain_db":-1.6,"q":5.31},{"type":"peak_dip","frequency":4712,"gain_db":-2.5,"q":6},{"type":"peak_dip","frequency":4102,"gain_db":1.4,"q":6}]},"product_id":"fiio::fh1"}}
{"type":"eq","id":"ghost::x::y","data":{"author":"Ghost","type":"parametric_eq","parameters":{"gain_db":-1,"bands":[{"type":"peak_dip","frequency":100,"gain_db":1,"q":1}]},"product_id":"ghost::x"}}
{"type":"eq","id":"fiio:fh1::synthetic","data":{"author":"Synthetic","type":"parametric_eq","parameters":{"gain_db":2,"bands":[{"type":"peak_dip","frequency":100,"gain_db":1,"q":1},{"type":"band_stop","frequency":200,"gain_db":0,"q":1}]},"product_id":"fiio::fh1"}}
{this line is not json
"""#

    func testCatalogAssemblyFromRealData() {
        let catalog = OpraImporter.parseCatalog(text: fixture)
        XCTAssertEqual(catalog.products.count, 1, "The unknown product's EQ must not invent a product")
        XCTAssertEqual(catalog.skippedLineCount, 1, "Only the garbage line is counted skipped")

        let product = catalog.products[0]
        XCTAssertEqual(product.name, "FH1")
        XCTAssertEqual(product.vendorName, "FiiO")
        XCTAssertEqual(product.presets.count, 3)

        let oratory = product.presets.first { $0.author == "oratory1990" }
        XCTAssertNotNil(oratory)
        XCTAssertEqual(oratory?.details, "USound Target")
        XCTAssertEqual(oratory?.bands.count, 7)
        XCTAssertTrue(oratory?.bands.allSatisfy { $0.filterType == .parametric } ?? false)
        XCTAssertEqual(oratory?.bands.first?.frequency ?? 0, 250, accuracy: 0.01)
        XCTAssertEqual(oratory?.bands.first?.gain ?? 0, -2.3, accuracy: 0.01)

        let autoEq = product.presets.first { $0.author == "AutoEQ" }
        XCTAssertEqual(autoEq?.bands.count, 10)
        XCTAssertEqual(autoEq?.bands.first?.filterType, .lowShelf)
        XCTAssertEqual(autoEq?.bands[5].filterType, .highShelf)
    }

    func testMakeProfileCarriesProvenance() {
        let catalog = OpraImporter.parseCatalog(text: fixture)
        let product = catalog.products[0]
        let oratory = product.presets.first { $0.author == "oratory1990" }!

        let result = OpraImporter.makeProfile(
            product: product, preset: oratory, deviceUID: "uid-1", deviceName: "FH1"
        )
        XCTAssertEqual(result.profile.sourceName, "OPRA: FH1")
        XCTAssertEqual(result.profile.author, "oratory1990")
        XCTAssertEqual(result.profile.sourceDetails, "USound Target")
        XCTAssertEqual(result.profile.preampDB, -7.6, accuracy: 0.001)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testUnsupportedBandsAndPositivePreampAreReported() {
        let catalog = OpraImporter.parseCatalog(text: fixture)
        let product = catalog.products[0]
        let synthetic = product.presets.first { $0.author == "Synthetic" }!
        XCTAssertEqual(synthetic.bands.count, 1)
        XCTAssertEqual(synthetic.skippedBandCount, 1)

        let result = OpraImporter.makeProfile(
            product: product, preset: synthetic, deviceUID: "uid-1", deviceName: "FH1"
        )
        XCTAssertEqual(result.profile.preampDB, 0, "Positive preamp clamps to 0, as in the AutoEq importer")
        XCTAssertTrue(result.warnings.contains { $0.contains("clamped") })
        XCTAssertTrue(result.warnings.contains { $0.contains("skipped") })
    }
}

/// Provenance survives the correction store, and profiles written
/// before A7 (no author keys) still decode.
final class CorrectionProvenanceStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.provenance.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testProvenanceRoundTrip() {
        let store = DeviceCorrectionStore(defaults: defaults)
        let profile = DeviceCorrectionProfile(
            deviceUID: "uid-9",
            deviceName: "FH1",
            sourceName: "OPRA: FH1",
            author: "oratory1990",
            sourceDetails: "USound Target",
            preampDB: -7.6,
            bands: []
        )
        store.save(profile)
        let loaded = store.profile(forUID: "uid-9")
        XCTAssertEqual(loaded?.author, "oratory1990")
        XCTAssertEqual(loaded?.sourceDetails, "USound Target")
    }
}
