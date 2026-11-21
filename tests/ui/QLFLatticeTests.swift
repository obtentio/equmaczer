// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// The QLF pure core: Bayer quantisation, bar frontier, geometry.
final class QLFLatticeTests: XCTestCase {

    func testLitCountFollowsTheBayerThresholds() {
        XCTAssertEqual(QLFLattice.litCount(occupancy: 0), 0)
        XCTAssertEqual(QLFLattice.litCount(occupancy: 0.1), 0)
        XCTAssertEqual(QLFLattice.litCount(occupancy: 0.125), 1)
        XCTAssertEqual(QLFLattice.litCount(occupancy: 0.37), 1)
        XCTAssertEqual(QLFLattice.litCount(occupancy: 0.375), 2)
        XCTAssertEqual(QLFLattice.litCount(occupancy: 0.625), 3)
        XCTAssertEqual(QLFLattice.litCount(occupancy: 0.875), 4)
        XCTAssertEqual(QLFLattice.litCount(occupancy: 1), 4)
    }

    func testLitCountClampsOutOfRangeOccupancy() {
        XCTAssertEqual(QLFLattice.litCount(occupancy: -0.5), 0)
        XCTAssertEqual(QLFLattice.litCount(occupancy: 2), 4)
    }

    func testSecondLitDotIsTheDiagonal() {
        let rects = QLFLattice.litRects(occupancy: 0.4, origin: .zero)
        XCTAssertEqual(rects.count, 2)
        // First: top-left sub-cell. Second: bottom-right (diagonal).
        XCTAssertEqual(rects[0].origin.x, 0.25, accuracy: 0.001)
        XCTAssertEqual(rects[0].origin.y, 0.25, accuracy: 0.001)
        XCTAssertEqual(rects[1].origin.x, 2.25, accuracy: 0.001)
        XCTAssertEqual(rects[1].origin.y, 2.25, accuracy: 0.001)
        XCTAssertEqual(rects[0].width, 1.5, accuracy: 0.001)
    }

    func testLitRectsOffsetByTheCellOrigin() {
        let rects = QLFLattice.litRects(occupancy: 1, origin: CGPoint(x: 40, y: 8))
        XCTAssertEqual(rects.count, 4)
        XCTAssertEqual(rects[0].origin.x, 40.25, accuracy: 0.001)
        XCTAssertEqual(rects[0].origin.y, 8.25, accuracy: 0.001)
    }

    func testBarOccupancyFrontier() {
        let bar = QLFLattice.barOccupancy(value: 0.55, cells: 10)
        XCTAssertEqual(bar.count, 10)
        XCTAssertEqual(bar[0..<5].reduce(0, +), 5, accuracy: 0.001)
        XCTAssertEqual(bar[5], 0.5, accuracy: 0.001)
        XCTAssertEqual(bar[6..<10].reduce(0, +), 0, accuracy: 0.001)
    }

    func testBarOccupancyExtremes() {
        XCTAssertEqual(QLFLattice.barOccupancy(value: 0, cells: 4), [0, 0, 0, 0])
        XCTAssertEqual(QLFLattice.barOccupancy(value: 1, cells: 4), [1, 1, 1, 1])
        XCTAssertEqual(QLFLattice.barOccupancy(value: 0.5, cells: 0), [])
    }

    func testNormalisedDB() {
        XCTAssertEqual(QLFLattice.normalised(db: -60), 0, accuracy: 0.001)
        XCTAssertEqual(QLFLattice.normalised(db: -30), 0.5, accuracy: 0.001)
        XCTAssertEqual(QLFLattice.normalised(db: 0), 1, accuracy: 0.001)
        XCTAssertEqual(QLFLattice.normalised(db: -90), 0, accuracy: 0.001)
        XCTAssertEqual(QLFLattice.normalised(db: 3), 1, accuracy: 0.001)
    }
}
