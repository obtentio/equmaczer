import Foundation
import Network

struct UpdateFetchResponse: Sendable {
    let data: Data
    let statusCode: Int
}

@MainActor
protocol UpdateFetching {
    func fetch(version: String) async throws -> UpdateFetchResponse
}

/// Anonymous, short-lived GET requests to the release channel.
@MainActor
struct UpdateFetchService: UpdateFetching {
    func fetch(version: String) async throws -> UpdateFetchResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/obtentio/equmaczer/releases/latest")!)
        request.httpMethod = "GET"
        request.setValue("equmaczer/\(version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return UpdateFetchResponse(data: data, statusCode: response.statusCode)
    }
}

@MainActor
protocol UpdateReachabilityProviding {
    var isReachable: Bool { get }
}

@MainActor
final class UpdateReachabilityService: UpdateReachabilityProviding {
    private let monitor = NWPathMonitor()
    var isReachable: Bool { monitor.currentPath.status == .satisfied }

    init() { monitor.start(queue: DispatchQueue(label: "com.obtentio.equmaczer.update-network")) }
    deinit { monitor.cancel() }
}
