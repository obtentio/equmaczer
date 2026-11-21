//  UpdateCheckServiceTests.swift
//  EqumaczerTests
//
//  Tests for UpdateCheckService pure functions.

import XCTest
@testable import equmaczer

final class UpdateCheckServiceTests: XCTestCase {

    // MARK: - isVersion(_:newerThan:)

    func testIsVersion_NewerPatch() {
        XCTAssertTrue(UpdateCheckService.isVersion("1.3.3", newerThan: "1.3.2"))
    }

    func testIsVersion_NewerMinor() {
        XCTAssertTrue(UpdateCheckService.isVersion("1.4.0", newerThan: "1.3.2"))
    }

    func testIsVersion_NewerMajor() {
        XCTAssertTrue(UpdateCheckService.isVersion("2.0.0", newerThan: "1.9.9"))
    }

    func testIsVersion_SameVersion() {
        XCTAssertFalse(UpdateCheckService.isVersion("1.3.2", newerThan: "1.3.2"))
    }

    func testIsVersion_OlderPatch() {
        XCTAssertFalse(UpdateCheckService.isVersion("1.3.1", newerThan: "1.3.2"))
    }

    func testIsVersion_OlderMinor() {
        XCTAssertFalse(UpdateCheckService.isVersion("1.2.9", newerThan: "1.3.2"))
    }

    func testIsVersion_NewerWithFewerComponents() {
        XCTAssertTrue(UpdateCheckService.isVersion("1.4", newerThan: "1.3.2"))
    }

    func testIsVersion_OlderWithFewerComponents() {
        XCTAssertFalse(UpdateCheckService.isVersion("1.3", newerThan: "1.3.2"))
    }

    func testIsVersion_EqualWithFewerComponents() {
        XCTAssertFalse(UpdateCheckService.isVersion("1.3", newerThan: "1.3.0"))
    }

    // MARK: - parseReleaseResponse

    func testParseReleaseResponse_ValidTagWithVPrefix() {
        let json = Data(#"{"tag_name":"v1.4.0","html_url":"https://github.com/obtentio/equmaczer/releases/tag/v1.4.0"}"#.utf8)
        XCTAssertEqual(UpdateCheckService.parseReleaseResponse(json, currentVersion: "1.3.5"),
            .updateAvailable(latestVersion: "1.4.0", releaseURL: URL(string: "https://github.com/obtentio/equmaczer/releases/tag/v1.4.0")!))
    }

    func testParseReleaseResponse_MissingTagName() {
        let json = """
        {"name": "Release 1.4.0"}
        """.data(using: .utf8)!

        let result = UpdateCheckService.parseReleaseResponse(json)

        if case .error(.parsingFailed) = result {
            // Expected
        } else {
            XCTFail("Expected parsingFailed for missing tag_name, got \(result)")
        }
    }

    func testParseReleaseResponse_InvalidJSON() {
        let data = "not json at all".data(using: .utf8)!

        let result = UpdateCheckService.parseReleaseResponse(data)

        if case .error(.parsingFailed) = result {
            // Expected
        } else {
            XCTFail("Expected parsingFailed for invalid JSON, got \(result)")
        }
    }

    func testParseReleaseResponse_EmptyTagName() {
        let json = """
        {"tag_name": ""}
        """.data(using: .utf8)!

        let result = UpdateCheckService.parseReleaseResponse(json)

        if case .error(.parsingFailed) = result {
            // Expected — empty version string
        } else {
            XCTFail("Expected parsingFailed for empty tag_name, got \(result)")
        }
    }
}

@MainActor
private final class FakeUpdateFetcher: UpdateFetching {
    var calls = 0
    var response = UpdateFetchResponse(data: Data(), statusCode: 404)
    var error: URLError?
    func fetch(version: String) async throws -> UpdateFetchResponse {
        calls += 1
        if let error { throw error }
        return response
    }
}

@MainActor
private final class FakeUpdateReachability: UpdateReachabilityProviding {
    var isReachable = true
}

@MainActor
final class UpdateChannelTests: XCTestCase {
    func testPrereleaseIsIgnored() {
        let data = Data(#"{"tag_name":"v9.0","prerelease":true,"html_url":"https://github.com/obtentio/equmaczer/releases/tag/v9.0"}"#.utf8)
        XCTAssertEqual(UpdateCheckService.parseReleaseResponse(data, currentVersion: "1.0"), .upToDate)
    }

    func testUpToDateAndMissingReleaseURL() {
        let data = Data(#"{"tag_name":"v1.0","html_url":"https://github.com/obtentio/equmaczer/releases/tag/v1.0"}"#.utf8)
        XCTAssertEqual(UpdateCheckService.parseReleaseResponse(data, currentVersion: "1.0"), .upToDate)
        XCTAssertEqual(UpdateCheckService.parseReleaseResponse(Data(#"{"tag_name":"v2.0"}"#.utf8), currentVersion: "1.0"), .error(.parsingFailed))
    }

    func test404ShowsNoReleases() async {
        let fetcher = FakeUpdateFetcher()
        let service = UpdateCheckService(fetcher: fetcher, reachability: FakeUpdateReachability(), version: "1.0")
        await service.forceCheckForUpdates()
        XCTAssertEqual(service.result, .noReleases)
        XCTAssertEqual(service.statusDetail(at: Date()), "No releases yet")
        XCTAssertFalse(service.isChecking)
        XCTAssertNil(service.releaseURL)
    }

    func testOfflineShowsNoConnection() async {
        let fetcher = FakeUpdateFetcher()
        fetcher.error = URLError(.notConnectedToInternet)
        let service = UpdateCheckService(fetcher: fetcher, reachability: FakeUpdateReachability(), version: "1.0")
        await service.forceCheckForUpdates()
        XCTAssertEqual(service.result, .error(.networkUnavailable))
        XCTAssertEqual(service.statusDetail(at: Date()), "Could not check, no connection")
        XCTAssertFalse(service.isChecking)
    }

    func testDailyLimitSkipsAutomaticButNotManual() async {
        let fetcher = FakeUpdateFetcher()
        let date = Date(timeIntervalSince1970: 100_000)
        let service = UpdateCheckService(fetcher: fetcher, reachability: FakeUpdateReachability(), version: "1.0", now: { date })
        await service.checkForUpdates()
        await service.checkForUpdates()
        XCTAssertEqual(fetcher.calls, 1)
        await service.forceCheckForUpdates()
        XCTAssertEqual(fetcher.calls, 2)
        XCTAssertEqual(service.lastCheckDate, date)
    }

    func testDailyLimitExpiresAndRestoredDateIsHonoured() async {
        let fetcher = FakeUpdateFetcher()
        let date = Date(timeIntervalSince1970: 200_000)
        let service = UpdateCheckService(fetcher: fetcher, reachability: FakeUpdateReachability(), version: "1.0", now: { date })
        service.lastCheckDate = date.addingTimeInterval(-86_399)
        await service.checkForUpdates()
        XCTAssertEqual(fetcher.calls, 0)
        service.lastCheckDate = date.addingTimeInterval(-86_400)
        await service.checkForUpdates()
        XCTAssertEqual(fetcher.calls, 1)
    }

    func testAutomaticSkipsDisabledAndUnreachableWithoutConsumingLimit() async {
        let fetcher = FakeUpdateFetcher()
        let reachability = FakeUpdateReachability()
        let service = UpdateCheckService(fetcher: fetcher, reachability: reachability, version: "1.0")
        service.automaticChecksEnabled = false
        await service.checkForUpdates()
        service.automaticChecksEnabled = true
        reachability.isReachable = false
        await service.checkForUpdates()
        XCTAssertEqual(fetcher.calls, 0)
        XCTAssertNil(service.lastCheckDate)
        reachability.isReachable = true
        await service.checkForUpdates()
        XCTAssertEqual(fetcher.calls, 1)
    }

    func testNewReleasePublishesDownloadAndUpToDateClearsIt() async {
        let fetcher = FakeUpdateFetcher()
        let url = URL(string: "https://github.com/obtentio/equmaczer/releases/tag/v2.0")!
        fetcher.response = UpdateFetchResponse(data: Data(#"{"tag_name":"v2.0","html_url":"https://github.com/obtentio/equmaczer/releases/tag/v2.0"}"#.utf8), statusCode: 200)
        let date = Date()
        let service = UpdateCheckService(fetcher: fetcher, reachability: FakeUpdateReachability(), version: "1.0", now: { date })
        await service.forceCheckForUpdates()
        XCTAssertTrue(service.updateAvailable)
        XCTAssertEqual(service.releaseURL, url)
        XCTAssertEqual(service.latestVersion, "2.0")
        XCTAssertEqual(service.statusDetail(at: date), "equmaczer 2.0 is out")
        fetcher.response = UpdateFetchResponse(data: Data(#"{"tag_name":"v1.0","html_url":"https://github.com/obtentio/equmaczer/releases/tag/v1.0"}"#.utf8), statusCode: 200)
        await service.forceCheckForUpdates()
        XCTAssertFalse(service.updateAvailable)
        XCTAssertEqual(service.statusDetail(at: date.addingTimeInterval(120)), "Up to date, checked 2 min ago")
    }

    func testSnapshotRoundTripAndOldSnapshotDefaults() throws {
        var snapshot = AppStateSnapshot.default
        snapshot.automaticUpdateChecksEnabled = false
        snapshot.lastUpdateCheckDate = Date(timeIntervalSince1970: 100_000)
        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(AppStateSnapshot.self, from: data)
        XCTAssertFalse(restored.automaticUpdateChecksEnabled)
        XCTAssertEqual(restored.lastUpdateCheckDate, snapshot.lastUpdateCheckDate)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "automaticUpdateChecksEnabled")
        json.removeValue(forKey: "lastUpdateCheckDate")
        let old = try JSONDecoder().decode(AppStateSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(old.automaticUpdateChecksEnabled)
        XCTAssertNil(old.lastUpdateCheckDate)
    }
}
