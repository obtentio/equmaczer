// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import XCTest
@testable import equmaczer

/// The driver status decision. The field failure these pin:
/// the driver installed 2026-11-13 carries the same version
/// (1.1.0) as the bundled driver under the pre-identity-pass
/// bundle ID — a version-only check called it "installed"
/// forever and the app never offered its own update.
final class DriverStatusTests: XCTestCase {
    func testMissingBundleIsNotInstalled() {
        XCTAssertEqual(
            DriverStatus.evaluate(bundleExists: false, installedVersion: nil, installedBundleID: nil, bundledVersion: "1.1.0"),
            .notInstalled
        )
    }

    func testIdentityMismatchAtEqualVersionNeedsUpdate() {
        XCTAssertEqual(
            DriverStatus.evaluate(bundleExists: true, installedVersion: "1.1.0", installedBundleID: "net.knage.equaliser.driver", bundledVersion: "1.1.0"),
            .needsUpdate(currentVersion: "1.1.0", bundledVersion: "1.1.0")
        )
    }

    func testOlderVersionNeedsUpdate() {
        XCTAssertEqual(
            DriverStatus.evaluate(bundleExists: true, installedVersion: "1.0.0", installedBundleID: DRIVER_BUNDLE_ID, bundledVersion: "1.1.0"),
            .needsUpdate(currentVersion: "1.0.0", bundledVersion: "1.1.0")
        )
    }

    func testVersionComparisonIsNumericAware() {
        XCTAssertEqual(
            DriverStatus.evaluate(bundleExists: true, installedVersion: "1.9.0", installedBundleID: DRIVER_BUNDLE_ID, bundledVersion: "1.10.0"),
            .needsUpdate(currentVersion: "1.9.0", bundledVersion: "1.10.0"),
            "a plain string comparison would call 1.9 newer than 1.10"
        )
    }

    func testCurrentDriverIsInstalled() {
        XCTAssertEqual(
            DriverStatus.evaluate(bundleExists: true, installedVersion: "1.1.0", installedBundleID: DRIVER_BUNDLE_ID, bundledVersion: "1.1.0"),
            .installed(version: "1.1.0")
        )
    }

    func testUnreadableVersionWithMatchingIdentityStaysInstalledUnknown() {
        XCTAssertEqual(
            DriverStatus.evaluate(bundleExists: true, installedVersion: nil, installedBundleID: DRIVER_BUNDLE_ID, bundledVersion: "1.1.0"),
            .installed(version: "unknown")
        )
    }
}
