// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).

import XCTest
@testable import equmaczer

final class IdentityMigrationServiceTests: XCTestCase {

    private var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        suiteNames = []
        super.tearDown()
    }

    private func makeSuite() -> (name: String, defaults: UserDefaults) {
        let name = "equmaczer-test-\(UUID().uuidString)"
        suiteNames.append(name)
        return (name, UserDefaults(suiteName: name)!)
    }

    func testMigratesApplicationKeysAndSetsSentinel() {
        let source = makeSuite()
        let target = makeSuite()
        source.defaults.set(6.0, forKey: "bandGain0")
        source.defaults.set("My Preset", forKey: "activePresetName")
        source.defaults.set(true, forKey: "NSNavPanelExpanded") // system key

        let migrated = IdentityMigrationService.migrateIfNeeded(
            arguments: ["equmaczer", "-migrateFromLegacyDomain", source.name],
            standard: target.defaults
        )

        XCTAssertTrue(migrated)
        XCTAssertEqual(target.defaults.double(forKey: "bandGain0"), 6.0)
        XCTAssertEqual(target.defaults.string(forKey: "activePresetName"), "My Preset")
        XCTAssertNil(target.defaults.object(forKey: "NSNavPanelExpanded"))
        XCTAssertTrue(target.defaults.bool(forKey: IdentityMigrationService.completionKey))
    }

    func testSecondRunIsNoOp() {
        let source = makeSuite()
        let target = makeSuite()
        source.defaults.set(1.0, forKey: "someKey")
        let arguments = ["equmaczer", "-migrateFromLegacyDomain", source.name]

        XCTAssertTrue(IdentityMigrationService.migrateIfNeeded(arguments: arguments, standard: target.defaults))
        source.defaults.set(2.0, forKey: "someKey")
        XCTAssertFalse(IdentityMigrationService.migrateIfNeeded(arguments: arguments, standard: target.defaults))
        XCTAssertEqual(target.defaults.double(forKey: "someKey"), 1.0)
    }

    func testNoArgumentMeansNoMigration() {
        let target = makeSuite()
        XCTAssertFalse(IdentityMigrationService.migrateIfNeeded(arguments: ["equmaczer"], standard: target.defaults))
        XCTAssertFalse(target.defaults.bool(forKey: IdentityMigrationService.completionKey))
    }

    func testEmptySourceDoesNotClaimCompletion() {
        let source = makeSuite()
        let target = makeSuite()
        let migrated = IdentityMigrationService.migrateIfNeeded(
            arguments: ["equmaczer", "-migrateFromLegacyDomain", source.name],
            standard: target.defaults
        )
        XCTAssertFalse(migrated)
        XCTAssertFalse(target.defaults.bool(forKey: IdentityMigrationService.completionKey))
    }

    func testLegacyDomainParsing() {
        XCTAssertEqual(
            IdentityMigrationService.legacyDomain(from: ["app", "-migrateFromLegacyDomain", "net.example.old"]),
            "net.example.old"
        )
        XCTAssertNil(IdentityMigrationService.legacyDomain(from: ["app", "-migrateFromLegacyDomain"]))
        XCTAssertNil(IdentityMigrationService.legacyDomain(from: ["app"]))
    }

    func testSystemKeyDetection() {
        XCTAssertTrue(IdentityMigrationService.isSystemKey("NSWindow Frame"))
        XCTAssertTrue(IdentityMigrationService.isSystemKey("AppleLanguages"))
        XCTAssertTrue(IdentityMigrationService.isSystemKey("com.apple.finder"))
        XCTAssertFalse(IdentityMigrationService.isSystemKey("activePresetName"))
    }
}
