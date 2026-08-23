//
//  TicketmasterAPIClient.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/23/26.
//

import Combine
import Foundation

enum TicketmasterError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case notConnected
    case invalidKey(String?)
    case serverError(Int)
    case connectionFailed(String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The request URL is invalid."
        case .invalidResponse:
            return "Ticketmaster returned an invalid response."
        case .notConnected:
            return "Not connected to Ticketmaster."
        case .invalidKey(let detail):
            let base = "That API key was rejected by Ticketmaster"
            let suffix = "Make sure you copied the \"Consumer Key\" (not the Secret) from My Apps."
            if let detail, !detail.isEmpty {
                return "\(base): \(detail). \(suffix)"
            }
            return "\(base). \(suffix)"
        case .serverError(let statusCode):
            return "Ticketmaster returned an error (status \(statusCode))."
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .decodingFailed:
            return "Failed to parse Ticketmaster's response."
        }
    }
}

struct TicketmasterEvent: Identifiable, Hashable {
    let id: String
    let name: String
    let date: Date?
    let venueName: String?
    let city: String?
    let stateCode: String?
    let countryCode: String?
    let eventURL: URL?
    let imageURL: URL?
}

/// Per-user Ticketmaster Discovery API access — unlike Jellyfin or Lidarr, there's no self-hosted
/// server to point at, so each user brings their own free Ticketmaster API key (see
/// `TicketmasterSettingsView` for the onboarding instructions), stored the same way Lidarr's is.
final class TicketmasterAPIClient: ObservableObject {
    static let shared = TicketmasterAPIClient()

    @Published var apiKey: String?
    @Published var isConnected: Bool = false

    private static let service = "com.bluefin.ticketmaster"
    private static let baseURL = URL(string: "https://app.ticketmaster.com/discovery/v2/")!

    private init() {
        loadCredentials()
    }

    private func loadCredentials() {
        guard let keyData = KeychainHelper.shared.read(service: Self.service, account: "api_key"),
              let key = String(data: keyData, encoding: .utf8), !key.isEmpty else {
            return
        }
        apiKey = key
        isConnected = true
    }

    func disconnect() {
        apiKey = nil
        isConnected = false
        KeychainHelper.shared.delete(service: Self.service, account: "api_key")
    }

    /// Validates the key against a real (minimal) request before persisting it, the same way
    /// `LidarrAPIClient.connect` checks the server before saving.
    func connect(apiKey: String) async throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw TicketmasterError.connectionFailed("API key is required.") }
        _ = try await fetchEvents(keyword: "test", apiKey: trimmedKey, size: 1)

        await MainActor.run {
            self.apiKey = trimmedKey
            self.isConnected = true
            KeychainHelper.shared.save(trimmedKey.data(using: .utf8)!, service: Self.service, account: "api_key")
        }
    }

    /// Upcoming, music-classified events matching `artistName`, filtered down to only the ones
    /// where Ticketmaster's own attraction data actually names this artist — a plain keyword search
    /// can otherwise surface unrelated events that merely mention the name somewhere (a venue, a
    /// support act, a similarly-named event).
    func fetchUpcomingConcerts(forArtist artistName: String) async throws -> [TicketmasterEvent] {
        guard let apiKey else { throw TicketmasterError.notConnected }
        let rawEvents = try await fetchEvents(keyword: artistName, apiKey: apiKey, size: 50)
        let normalizedArtistName = Self.normalize(artistName)

        return rawEvents
            .compactMap { raw -> TicketmasterEvent? in
                let attractionNames = raw.embedded?.attractions?.compactMap(\.name) ?? []
                guard attractionNames.contains(where: { Self.normalize($0) == normalizedArtistName }) else { return nil }
                return TicketmasterEvent(raw: raw)
            }
            .filter { ($0.date ?? .distantPast) >= .now }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    private func fetchEvents(keyword: String, apiKey: String, size: Int) async throws -> [TicketmasterRawEvent] {
        guard var components = URLComponents(url: Self.baseURL.appendingPathComponent("events.json"), resolvingAgainstBaseURL: false) else {
            throw TicketmasterError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "classificationName", value: "music"),
            URLQueryItem(name: "sort", value: "date,asc"),
            URLQueryItem(name: "size", value: String(size))
        ]
        guard let url = components.url else { throw TicketmasterError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw TicketmasterError.invalidResponse }
        if httpResponse.statusCode == 401 {
            throw TicketmasterError.invalidKey(Self.faultString(from: data))
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw TicketmasterError.serverError(httpResponse.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(TicketmasterEventsResponse.self, from: data)
            return decoded.embedded?.events ?? []
        } catch {
            throw TicketmasterError.decodingFailed
        }
    }

    private static func normalize(_ string: String) -> String {
        string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ticketmaster's error responses carry their own explanation (e.g. "Invalid ApiKey for given
    /// resource") in this shape — surfacing it directly is far more actionable than a generic
    /// "rejected" message, since it's Ticketmaster's own diagnosis rather than a guess.
    private static func faultString(from data: Data) -> String? {
        struct FaultResponse: Decodable {
            let fault: Fault?
            struct Fault: Decodable { let faultstring: String? }
        }
        return (try? JSONDecoder().decode(FaultResponse.self, from: data))?.fault?.faultstring
    }
}

// MARK: - Discovery API response shape

private struct TicketmasterEventsResponse: Decodable {
    let embedded: Embedded?
    enum CodingKeys: String, CodingKey { case embedded = "_embedded" }
    struct Embedded: Decodable { let events: [TicketmasterRawEvent] }
}

private struct TicketmasterRawEvent: Decodable {
    let id: String
    let name: String
    let url: String?
    let images: [RawImage]?
    let dates: RawDates
    let embedded: Embedded?
    enum CodingKeys: String, CodingKey { case id, name, url, images, dates, embedded = "_embedded" }

    struct RawImage: Decodable { let url: String; let width: Int? }

    struct RawDates: Decodable {
        let start: RawStart
        struct RawStart: Decodable { let localDate: String?; let dateTime: String? }
    }

    struct Embedded: Decodable {
        let venues: [RawVenue]?
        let attractions: [RawAttraction]?
    }

    struct RawVenue: Decodable {
        let name: String?
        let city: RawCity?
        let state: RawState?
        let country: RawCountry?
        struct RawCity: Decodable { let name: String? }
        struct RawState: Decodable { let stateCode: String? }
        struct RawCountry: Decodable { let countryCode: String? }
    }

    struct RawAttraction: Decodable { let name: String? }
}

private extension TicketmasterEvent {
    /// Prefers `dateTime` (an absolute instant, so it sorts and compares correctly across time
    /// zones) and falls back to parsing `localDate` alone (as a UTC midnight) for the rare event
    /// that only has a date announced yet, no time.
    init(raw: TicketmasterRawEvent) {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "UTC")

        let date = raw.dates.start.dateTime.flatMap(isoFormatter.date(from:))
            ?? raw.dates.start.localDate.flatMap(dayFormatter.date(from:))

        let venue = raw.embedded?.venues?.first
        let widestImage = raw.images?.max { ($0.width ?? 0) < ($1.width ?? 0) }

        self.init(
            id: raw.id,
            name: raw.name,
            date: date,
            venueName: venue?.name,
            city: venue?.city?.name,
            stateCode: venue?.state?.stateCode,
            countryCode: venue?.country?.countryCode,
            eventURL: raw.url.flatMap(URL.init),
            imageURL: widestImage.flatMap { URL(string: $0.url) }
        )
    }
}
