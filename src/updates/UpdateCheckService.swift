// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
// Checks GitHub Releases and offers the release page; never installs updates.

import Foundation

@MainActor
final class UpdateCheckService: ObservableObject, UpdateChecking {
    @Published private(set) var result: UpdateCheckResult?
    @Published private(set) var isChecking = false
    @Published var automaticChecksEnabled = true
    @Published var lastCheckDate: Date?

    var updateAvailable: Bool { releaseURL != nil }
    var latestVersion: String? {
        if case .updateAvailable(let version, _) = result { return version }
        return nil
    }
    var releaseURL: URL? {
        if case .updateAvailable(_, let url) = result { return url }
        return nil
    }

    private let fetcher: any UpdateFetching
    private let reachability: any UpdateReachabilityProviding
    private let version: String
    private let now: () -> Date
    private var timer: DispatchSourceTimer?
    var onCheck: (() -> Void)?

    init(fetcher: any UpdateFetching = UpdateFetchService(),
         reachability: any UpdateReachabilityProviding = UpdateReachabilityService(),
         version: String = UpdateCheckService.currentAppVersion(), now: @escaping () -> Date = Date.init) {
        self.fetcher = fetcher
        self.reachability = reachability
        self.version = version
        self.now = now
    }

    /// First opportunity is ten seconds after launch; retry offline opportunities quietly.
    func startAutomaticChecks() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 10, repeating: 60)
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in await self?.checkForUpdates() }
        }
        self.timer = timer
        timer.resume()
    }

    deinit { timer?.cancel() }

    func checkForUpdates() async {
        guard automaticChecksEnabled, reachability.isReachable,
              lastCheckDate.map({ now().timeIntervalSince($0) >= 24 * 60 * 60 }) ?? true else { return }
        await forceCheckForUpdates()
    }

    func forceCheckForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        lastCheckDate = now()
        onCheck?()
        defer { isChecking = false }
        do {
            let response = try await fetcher.fetch(version: version)
            switch response.statusCode {
            case 404: result = .noReleases
            case 200: result = Self.parseReleaseResponse(response.data, currentVersion: version)
            default: result = .error(.invalidResponse)
            }
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                result = .error(.networkUnavailable)
            default: result = .error(.invalidResponse)
            }
        } catch {
            result = .error(.invalidResponse)
        }
    }

    func statusDetail(at date: Date) -> String {
        switch result {
        case .updateAvailable(let version, _): return "equmaczer \(version) is out"
        case .noReleases: return "No releases yet"
        case .error(.networkUnavailable): return "Could not check, no connection"
        case .error: return "Could not check, try again"
        case .upToDate:
            let minutes = max(0, Int(date.timeIntervalSince(lastCheckDate ?? date) / 60))
            if minutes == 0 { return "Up to date, checked just now" }
            if minutes < 60 { return "Up to date, checked \(minutes) min ago" }
            return "Up to date, checked \(minutes / 60) h ago"
        case nil: return "Not checked yet"
        }
    }

    // MARK: - Parsing (pure)

    nonisolated static func parseReleaseResponse(_ data: Data, currentVersion: String = currentAppVersion()) -> UpdateCheckResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .error(.parsingFailed)
        }
        if json["prerelease"] as? Bool == true { return .upToDate }
        guard let tag = json["tag_name"] as? String,
              let link = json["html_url"] as? String,
              let url = URL(string: link), url.scheme == "https", url.host == "github.com",
              url.path.hasPrefix("/obtentio/equmaczer/releases/"), !currentVersion.isEmpty else {
            return .error(.parsingFailed)
        }
        let latestVersion = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard !latestVersion.isEmpty else { return .error(.parsingFailed) }
        return isVersion(latestVersion, newerThan: currentVersion)
            ? .updateAvailable(latestVersion: latestVersion, releaseURL: url) : .upToDate
    }

    // MARK: - Version Comparison (pure)

    nonisolated static func currentAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    nonisolated static func isVersion(_ version: String, newerThan other: String) -> Bool {
        let versionComponents = version.split(separator: ".").compactMap { Int($0) }
        let otherComponents = other.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(versionComponents.count, otherComponents.count)
        let paddedVersion = versionComponents + Array(repeating: 0, count: maxCount - versionComponents.count)
        let paddedOther = otherComponents + Array(repeating: 0, count: maxCount - otherComponents.count)

        for (v, o) in zip(paddedVersion, paddedOther) {
            if v > o { return true }
            if v < o { return false }
        }
        return false
    }
}
