//
//  LidarrAPIClient.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/21/26.
//

import Foundation
import Combine

enum LidarrError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case notConnected
    case serverError(Int)
    case connectionFailed(String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server URL is invalid."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .notConnected:
            return "Not connected to a Lidarr server."
        case .serverError(let statusCode):
            return "The server returned an error (status \(statusCode))."
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .decodingFailed:
            return "Failed to parse the server response."
        }
    }
}

struct LidarrImage: Codable {
    let coverType: String
    let url: String?
    let remoteUrl: String?
}

struct LidarrArtist: Codable {
    let id: Int
    let artistName: String
    let images: [LidarrImage]?
}

/// A single entry from Lidarr's `/calendar` endpoint — an album release (past or upcoming) for a
/// monitored artist in the user's Lidarr library.
struct LidarrCalendarItem: Codable, Identifiable {
    let id: Int
    let title: String
    let releaseDate: Date?
    let monitored: Bool
    let images: [LidarrImage]?
    let artist: LidarrArtist?

    var artistName: String { artist?.artistName ?? "" }

    /// Prefers the album's own cover; falls back to the artist's image if the album has none yet
    /// (common for a release that hasn't dropped).
    private var coverImage: LidarrImage? {
        images?.first { $0.coverType == "cover" } ?? artist?.images?.first { $0.coverType == "poster" || $0.coverType == "fanart" }
    }

    /// Lidarr's `remoteUrl` (when present) points at the metadata provider's own CDN and needs no
    /// auth — used in preference to `url`, which is served by Lidarr itself and would need an
    /// `apikey` query parameter to load.
    func coverImageURL(serverURL: URL?, apiKey: String?) -> URL? {
        guard let coverImage else { return nil }
        if let remoteUrlString = coverImage.remoteUrl, let remoteURL = URL(string: remoteUrlString) {
            return remoteURL
        }
        guard let path = coverImage.url, let serverURL, let apiKey else { return nil }
        var components = URLComponents(url: serverURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "apikey", value: apiKey)]
        return components?.url
    }
}

final class LidarrAPIClient: ObservableObject {
    static let shared = LidarrAPIClient()

    @Published var serverURL: URL?
    @Published var apiKey: String?
    @Published var isConnected: Bool = false

    private static let service = "com.bluefin.lidarr"

    private init() {
        loadCredentials()
    }

    private func loadCredentials() {
        guard let urlData = KeychainHelper.shared.read(service: Self.service, account: "server_url"),
              let urlString = String(data: urlData, encoding: .utf8),
              let url = URL(string: urlString),
              let keyData = KeychainHelper.shared.read(service: Self.service, account: "api_key"),
              let key = String(data: keyData, encoding: .utf8) else {
            return
        }
        self.serverURL = url
        self.apiKey = key
        self.isConnected = true
    }

    private func saveCredentials(serverURL: URL, apiKey: String) {
        self.serverURL = serverURL
        self.apiKey = apiKey
        self.isConnected = true

        KeychainHelper.shared.save(serverURL.absoluteString.data(using: .utf8)!, service: Self.service, account: "server_url")
        KeychainHelper.shared.save(apiKey.data(using: .utf8)!, service: Self.service, account: "api_key")
    }

    func disconnect() {
        serverURL = nil
        apiKey = nil
        isConnected = false

        KeychainHelper.shared.delete(service: Self.service, account: "server_url")
        KeychainHelper.shared.delete(service: Self.service, account: "api_key")
    }

    /// Validates the server URL and API key against Lidarr's own status endpoint, then persists
    /// them only once that round trip succeeds.
    func connect(urlString: String, apiKey: String) async throws {
        var cleanUrlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanUrlString.lowercased().hasPrefix("http://") && !cleanUrlString.lowercased().hasPrefix("https://") {
            cleanUrlString = "http://" + cleanUrlString
        }
        guard let url = URL(string: cleanUrlString) else { throw LidarrError.invalidURL }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw LidarrError.connectionFailed("API key is required.") }

        _ = try await checkServerConnection(url: url, apiKey: trimmedKey)

        await MainActor.run {
            self.saveCredentials(serverURL: url, apiKey: trimmedKey)
        }
    }

    private func checkServerConnection(url: URL, apiKey: String) async throws -> String {
        let testURL = url.appendingPathComponent("api/v1/system/status")
        var components = URLComponents(url: testURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "apikey", value: apiKey)]
        guard let requestURL = components?.url else { throw LidarrError.invalidURL }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw LidarrError.invalidResponse }
            if httpResponse.statusCode == 401 {
                throw LidarrError.connectionFailed("Invalid API key.")
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw LidarrError.serverError(httpResponse.statusCode)
            }

            struct SystemStatus: Codable { let instanceName: String? }
            let status = try JSONDecoder().decode(SystemStatus.self, from: data)
            return status.instanceName ?? "Lidarr"
        } catch let error as LidarrError {
            throw error
        } catch {
            throw LidarrError.connectionFailed(error.localizedDescription)
        }
    }

    private func performGet<T: Decodable>(path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        guard let serverURL, let apiKey else { throw LidarrError.notConnected }
        guard var components = URLComponents(url: serverURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw LidarrError.invalidURL
        }
        components.queryItems = queryItems + [URLQueryItem(name: "apikey", value: apiKey)]
        guard let url = components.url else { throw LidarrError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw LidarrError.invalidResponse }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw LidarrError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw LidarrError.decodingFailed
        }
    }

    /// Upcoming, monitored album releases — the only thing the Home screen's "Upcoming Releases"
    /// section shows, so past releases and unmonitored (not-followed) artists/albums are filtered
    /// out here rather than in the view.
    func fetchUpcomingReleases(daysAhead: Int = 90) async throws -> [LidarrCalendarItem] {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: .now)
        guard let end = calendar.date(byAdding: .day, value: daysAhead, to: start) else { return [] }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let items: [LidarrCalendarItem] = try await performGet(
            path: "api/v1/calendar",
            queryItems: [
                URLQueryItem(name: "start", value: formatter.string(from: start)),
                URLQueryItem(name: "end", value: formatter.string(from: end)),
                URLQueryItem(name: "includeArtist", value: "true")
            ]
        )

        return items
            .filter { $0.monitored && ($0.releaseDate.map { $0 >= start } ?? false) }
            .sorted { ($0.releaseDate ?? .distantFuture) < ($1.releaseDate ?? .distantFuture) }
    }
}
