// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation
import XCTest
@testable import equmaczer

final class DriverInstallScriptTests: XCTestCase {
    func testShellPathRoundTripWithoutExpansion() throws {
        let value = "/tmp/Sam's \"EQ\" $(touch should-not-exist) `whoami` \\ folder\nnext line"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '%s' " + DriverInstallScript.shellLiteral(value)]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), value)
    }

    func testMissingSourcePreservesInstalledDriverAndCleansStaging() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("driver-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installed = directory.appendingPathComponent("equmaczer.driver")
        try Data("previous driver".utf8).write(to: installed)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", DriverInstallScript.install(source: directory.appendingPathComponent("missing's.driver").path,
            directory: directory.path, destination: installed.path,
            legacy: directory.appendingPathComponent("legacy.driver").path)]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertEqual(try String(contentsOf: installed, encoding: .utf8), "previous driver")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["equmaczer.driver"])
    }

    func testAppleScriptLiteralRoundTripsTheCompleteOperation() throws {
        let path = "/tmp/Sam's \"EQ\" \\ path\nfolder"
        let operation = DriverInstallScript.install(source: path, directory: "/tmp", destination: "/tmp/unused.driver", legacy: "/tmp/unused-legacy.driver")
        let script = try XCTUnwrap(NSAppleScript(source: "return \(DriverInstallScript.appleScriptLiteral(operation))"))
        var error: NSDictionary?
        XCTAssertTrue(script.compileAndReturnError(&error), "\(String(describing: error))")
        // Evaluate only a constant string, not the shell operation or any UI action.
        let result = script.executeAndReturnError(&error)
        XCTAssertNil(error)
        XCTAssertEqual(result.stringValue, operation)
    }
}
