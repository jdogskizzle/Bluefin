//
//  JellyfinAPIClient.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Foundation
import Combine

enum JellyfinError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case authenticationFailed
    case sessionExpired
    case serverError(Int)
    case connectionFailed(String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server URL is invalid."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .authenticationFailed:
            return "Invalid username or password."
        case .sessionExpired:
            return "Your session has expired. Please sign in again."
        case .serverError(let statusCode):
            return "The server returned an error (status \(statusCode))."
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .decodingFailed:
            return "Failed to parse the server response."
        }
    }
}

class JellyfinAPIClient: ObservableObject {
    static let shared = JellyfinAPIClient()
    
    @Published var serverURL: URL?
    @Published var accessToken: String?
    @Published var userId: String?
    @Published var isAuthorized: Bool = false
    @Published var selectedLibraryId: String?

    private let clientName = "Bluefin"
    private let deviceName = "iOS Device"
    private let version = "1.0.0"
    private let deviceIdDefaultsKey = "com.bluefin.deviceId"

    /// A stable ID unique to this install. Jellyfin ties access tokens to the device ID, so
    /// sharing one across installs (as a hardcoded constant would) makes the server treat
    /// separate installs as the same device and can invalidate each other's sessions.
    private lazy var deviceId: String = {
        if let existing = UserDefaults.standard.string(forKey: deviceIdDefaultsKey) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: deviceIdDefaultsKey)
        return newId
    }()
    private let selectedLibraryDefaultsKey = "selectedLibraryId"

    private init() {
        loadCredentials()
    }
    
    private func getAuthorizationHeader() -> String {
        var authHeader = "MediaBrowser Client=\"\(clientName)\", Device=\"\(deviceName)\", DeviceId=\"\(deviceId)\", Version=\"\(version)\""
        if let token = accessToken {
            authHeader += ", Token=\"\(token)\""
        }
        return authHeader
    }
    
    func saveCredentials(serverURL: URL, accessToken: String, userId: String) {
        self.serverURL = serverURL
        self.accessToken = accessToken
        self.userId = userId
        self.isAuthorized = true
        
        KeychainHelper.shared.save(serverURL.absoluteString.data(using: .utf8)!, service: "com.bluefin.app", account: "server_url")
        KeychainHelper.shared.save(accessToken.data(using: .utf8)!, service: "com.bluefin.app", account: "access_token")
        KeychainHelper.shared.save(userId.data(using: .utf8)!, service: "com.bluefin.app", account: "user_id")
    }
    
    func loadCredentials() {
        guard let urlData = KeychainHelper.shared.read(service: "com.bluefin.app", account: "server_url"),
              let urlString = String(data: urlData, encoding: .utf8),
              let url = URL(string: urlString),
              let tokenData = KeychainHelper.shared.read(service: "com.bluefin.app", account: "access_token"),
              let token = String(data: tokenData, encoding: .utf8),
              let userIdData = KeychainHelper.shared.read(service: "com.bluefin.app", account: "user_id"),
              let storedUserId = String(data: userIdData, encoding: .utf8) else {
            logout()
            return
        }
        
        self.serverURL = url
        self.accessToken = token
        self.userId = storedUserId
        self.isAuthorized = true
        self.selectedLibraryId = UserDefaults.standard.string(forKey: selectedLibraryDefaultsKey)
    }

    func logout() {
        self.serverURL = nil
        self.accessToken = nil
        self.userId = nil
        self.isAuthorized = false
        self.selectedLibraryId = nil

        KeychainHelper.shared.delete(service: "com.bluefin.app", account: "server_url")
        KeychainHelper.shared.delete(service: "com.bluefin.app", account: "access_token")
        KeychainHelper.shared.delete(service: "com.bluefin.app", account: "user_id")
        UserDefaults.standard.removeObject(forKey: selectedLibraryDefaultsKey)
    }

    func setSelectedLibrary(_ id: String?) {
        selectedLibraryId = id
        if let id {
            UserDefaults.standard.set(id, forKey: selectedLibraryDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedLibraryDefaultsKey)
        }
    }
    
    func checkServerConnection(url: URL) async throws -> String {
        let testURL = url.appendingPathComponent("System/Info/Public")
        var request = URLRequest(url: testURL)
        request.httpMethod = "GET"
        request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "X-Emby-Authorization")
        request.timeoutInterval = 10
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw JellyfinError.invalidResponse
            }
            
            struct PublicSystemInfo: Codable {
                let ServerName: String
                let LocalAddress: String?
            }
            
            let decoder = JSONDecoder()
            let info = try decoder.decode(PublicSystemInfo.self, from: data)
            return info.ServerName
        } catch {
            throw JellyfinError.connectionFailed(error.localizedDescription)
        }
    }
    
    func authenticate(urlString: String, username: String, secret: String) async throws {
        var cleanUrlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanUrlString.lowercased().hasPrefix("http://") && !cleanUrlString.lowercased().hasPrefix("https://") {
            cleanUrlString = "http://" + cleanUrlString
        }
        
        guard let url = URL(string: cleanUrlString) else {
            throw JellyfinError.invalidURL
        }
        
        let _ = try await checkServerConnection(url: url)
        
        let authURL = url.appendingPathComponent("Users/AuthenticateByName")
        var request = URLRequest(url: authURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "X-Emby-Authorization")
        
        let body: [String: String] = [
            "Username": username,
            "Pw": secret
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw JellyfinError.invalidResponse
            }
            
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw JellyfinError.authenticationFailed
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw JellyfinError.invalidResponse
            }
            
            struct AuthResponse: Codable {
                struct User: Codable {
                    let Id: String
                }
                let AccessToken: String
                let User: User
            }
            
            let decoder = JSONDecoder()
            let result = try decoder.decode(AuthResponse.self, from: data)
            
            DispatchQueue.main.async {
                self.saveCredentials(serverURL: url, accessToken: result.AccessToken, userId: result.User.Id)
            }
        } catch let error as JellyfinError {
            throw error
        } catch {
            throw JellyfinError.connectionFailed(error.localizedDescription)
        }
    }

    private func performGet<T: Decodable>(path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        guard let serverURL else { throw JellyfinError.invalidURL }
        guard var components = URLComponents(url: serverURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw JellyfinError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw JellyfinError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "X-Emby-Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JellyfinError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            await MainActor.run { self.logout() }
            throw JellyfinError.sessionExpired
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw JellyfinError.serverError(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw JellyfinError.decodingFailed
        }
    }

    func fetchLibraries() async throws -> [BaseItemDto] {
        guard let userId else { throw JellyfinError.invalidResponse }
        let response: ItemsResponse = try await performGet(path: "Users/\(userId)/Views")
        return response.Items
    }

    func fetchItems(
        parentId: String? = nil,
        includeItemTypes: String,
        recursive: Bool = true,
        artistIds: String? = nil,
        mediaTypes: String? = nil,
        searchTerm: String? = nil,
        sortBy: String = "SortName",
        fields: String? = nil
    ) async throws -> [BaseItemDto] {
        guard let userId else { throw JellyfinError.invalidResponse }
        var queryItems = [
            URLQueryItem(name: "IncludeItemTypes", value: includeItemTypes),
            URLQueryItem(name: "Recursive", value: String(recursive)),
            URLQueryItem(name: "SortBy", value: sortBy)
        ]
        if let parentId {
            queryItems.append(URLQueryItem(name: "ParentId", value: parentId))
        }
        if let artistIds {
            queryItems.append(URLQueryItem(name: "ArtistIds", value: artistIds))
        }
        if let mediaTypes {
            queryItems.append(URLQueryItem(name: "MediaTypes", value: mediaTypes))
        }
        if let searchTerm, !searchTerm.isEmpty {
            queryItems.append(URLQueryItem(name: "SearchTerm", value: searchTerm))
        }
        if let fields {
            // Jellyfin only includes a handful of fields by default — anything else (like
            // `PremiereDate`, needed for precise release-date sorting) has to be asked for
            // explicitly or it's simply absent from the response.
            queryItems.append(URLQueryItem(name: "Fields", value: fields))
        }

        let response: ItemsResponse = try await performGet(path: "Users/\(userId)/Items", queryItems: queryItems)
        return response.Items
    }

    /// Genres aren't real library items, so they don't come back from `Users/{userId}/Items` even
    /// with `IncludeItemTypes=MusicGenre` — Jellyfin exposes them only through this dedicated
    /// endpoint instead.
    func fetchGenres(parentId: String) async throws -> [BaseItemDto] {
        guard let userId else { throw JellyfinError.invalidResponse }
        let response: ItemsResponse = try await performGet(
            path: "MusicGenres",
            queryItems: [
                URLQueryItem(name: "userId", value: userId),
                URLQueryItem(name: "ParentId", value: parentId)
            ]
        )
        return response.Items
    }

    func fetchPlaylistItems(playlistId: String, fields: String? = nil) async throws -> [BaseItemDto] {
        guard let userId else { throw JellyfinError.invalidResponse }
        var queryItems = [URLQueryItem(name: "userId", value: userId)]
        if let fields {
            queryItems.append(URLQueryItem(name: "Fields", value: fields))
        }
        let response: ItemsResponse = try await performGet(
            path: "Playlists/\(playlistId)/Items",
            queryItems: queryItems
        )
        return response.Items
    }

    func addItemToPlaylist(playlistId: String, itemId: String) async throws {
        guard let userId else { throw JellyfinError.invalidResponse }
        guard let serverURL else { throw JellyfinError.invalidURL }
        guard var components = URLComponents(url: serverURL.appendingPathComponent("Playlists/\(playlistId)/Items"), resolvingAgainstBaseURL: false) else {
            throw JellyfinError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "ids", value: itemId),
            URLQueryItem(name: "userId", value: userId)
        ]
        guard let url = components.url else { throw JellyfinError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "X-Emby-Authorization")
        request.timeoutInterval = 10

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw JellyfinError.invalidResponse }

        if httpResponse.statusCode == 401 {
            await MainActor.run { self.logout() }
            throw JellyfinError.sessionExpired
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw JellyfinError.serverError(httpResponse.statusCode)
        }
    }

    /// `entryId` is the playlist entry to remove — `BaseItemDto.PlaylistItemId` for a song fetched
    /// as part of a playlist, not the song's own `Id` — since Jellyfin allows the same song to
    /// appear in a playlist more than once and needs to know which occurrence to remove.
    func removeItemFromPlaylist(playlistId: String, entryId: String) async throws {
        try await removeItemsFromPlaylist(playlistId: playlistId, entryIds: [entryId])
    }

    /// Same as `removeItemFromPlaylist`, batched into a single request — used by the playlist
    /// editor's multi-select delete instead of one request per selected song.
    func removeItemsFromPlaylist(playlistId: String, entryIds: [String]) async throws {
        guard let serverURL else { throw JellyfinError.invalidURL }
        guard var components = URLComponents(url: serverURL.appendingPathComponent("Playlists/\(playlistId)/Items"), resolvingAgainstBaseURL: false) else {
            throw JellyfinError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "entryIds", value: entryIds.joined(separator: ","))]
        guard let url = components.url else { throw JellyfinError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "X-Emby-Authorization")
        request.timeoutInterval = 10

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw JellyfinError.invalidResponse }

        if httpResponse.statusCode == 401 {
            await MainActor.run { self.logout() }
            throw JellyfinError.sessionExpired
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw JellyfinError.serverError(httpResponse.statusCode)
        }
    }

    /// Shared plumbing for the simple "fire a request, check the status code" playlist-management
    /// calls below — an optional JSON `body` and `contentType` cover the ones that need a request
    /// body (create/rename), everything else is headers-and-status-code only.
    private func performRequest(_ url: URL, method: String, body: Data? = nil, contentType: String? = nil) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "X-Emby-Authorization")
        request.timeoutInterval = 10
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw JellyfinError.invalidResponse }
        if httpResponse.statusCode == 401 {
            await MainActor.run { self.logout() }
            throw JellyfinError.sessionExpired
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw JellyfinError.serverError(httpResponse.statusCode)
        }
    }

    /// Creates an empty playlist and returns its new id.
    func createPlaylist(name: String) async throws -> String {
        guard let serverURL, let userId else { throw JellyfinError.invalidResponse }
        let url = serverURL.appendingPathComponent("Playlists")
        let body = try JSONSerialization.data(withJSONObject: [
            "Name": name,
            "Ids": [String](),
            "UserId": userId,
            "MediaType": "Audio"
        ])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "X-Emby-Authorization")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw JellyfinError.invalidResponse }
        if httpResponse.statusCode == 401 {
            await MainActor.run { self.logout() }
            throw JellyfinError.sessionExpired
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw JellyfinError.serverError(httpResponse.statusCode)
        }

        struct CreatePlaylistResponse: Codable { let Id: String }
        return try JSONDecoder().decode(CreatePlaylistResponse.self, from: data).Id
    }

    /// Deletes any item the user owns/can delete — used here for whole playlists, which Jellyfin
    /// stores as a regular library item.
    func deleteItem(itemId: String) async throws {
        guard let serverURL else { throw JellyfinError.invalidURL }
        try await performRequest(serverURL.appendingPathComponent("Items/\(itemId)"), method: "DELETE")
    }

    func renamePlaylist(playlistId: String, name: String) async throws {
        guard let serverURL else { throw JellyfinError.invalidURL }
        let body = try JSONSerialization.data(withJSONObject: ["Name": name])
        try await performRequest(
            serverURL.appendingPathComponent("Playlists/\(playlistId)"),
            method: "POST",
            body: body,
            contentType: "application/json"
        )
    }

    /// Moves the playlist entry (see `removeItemFromPlaylist` re: `entryId`) to `toIndex` within
    /// the playlist's order.
    func movePlaylistItem(playlistId: String, entryId: String, toIndex: Int) async throws {
        guard let serverURL else { throw JellyfinError.invalidURL }
        try await performRequest(
            serverURL.appendingPathComponent("Playlists/\(playlistId)/Items/\(entryId)/Move/\(toIndex)"),
            method: "POST"
        )
    }

    /// Uploads new cover art for any item — used here for a playlist's image. Jellyfin expects the
    /// image bytes base64-encoded in the body, with `Content-Type` set to the image's real MIME type.
    func uploadItemImage(itemId: String, imageData: Data, mimeType: String) async throws {
        guard let serverURL else { throw JellyfinError.invalidURL }
        try await performRequest(
            serverURL.appendingPathComponent("Items/\(itemId)/Images/Primary"),
            method: "POST",
            body: imageData.base64EncodedData(),
            contentType: mimeType
        )
    }

    func markFavorite(itemId: String) async throws {
        try await setFavorite(itemId: itemId, isFavorite: true)
    }

    func unmarkFavorite(itemId: String) async throws {
        try await setFavorite(itemId: itemId, isFavorite: false)
    }

    private func setFavorite(itemId: String, isFavorite: Bool) async throws {
        guard let serverURL, let userId else { throw JellyfinError.invalidResponse }
        let url = serverURL.appendingPathComponent("Users/\(userId)/FavoriteItems/\(itemId)")

        var request = URLRequest(url: url)
        request.httpMethod = isFavorite ? "POST" : "DELETE"
        request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "X-Emby-Authorization")
        request.timeoutInterval = 10

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw JellyfinError.invalidResponse }

        if httpResponse.statusCode == 401 {
            await MainActor.run { self.logout() }
            throw JellyfinError.sessionExpired
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw JellyfinError.serverError(httpResponse.statusCode)
        }
    }

    func fetchLyrics(itemId: String) async throws -> [LyricLine] {
        let response: LyricsResponse = try await performGet(path: "Audio/\(itemId)/Lyrics")
        return response.Lyrics
    }

    private func performPost(path: String, body: [String: Any]) async {
        guard let serverURL else { return }
        var request = URLRequest(url: serverURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "X-Emby-Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        // Reporting is best-effort — a dropped report shouldn't interrupt playback, so failures
        // (including a session that's expired) are silently swallowed rather than surfaced.
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Tells Jellyfin a play session has begun, so its "Now Playing" panel and per-item resume
    /// position start tracking this item.
    func reportPlaybackStart(itemId: String, playSessionId: String, positionTicks: Int64) async {
        await performPost(path: "Sessions/Playing", body: [
            "ItemId": itemId,
            "PlaySessionId": playSessionId,
            "PositionTicks": positionTicks,
            "IsPaused": false,
            "CanSeek": true,
            "PlayMethod": "DirectStream"
        ])
    }

    /// Periodic/event-driven position update for an in-progress session (play/pause toggles, seeks,
    /// and every `progressReportInterval` while actively playing).
    func reportPlaybackProgress(itemId: String, playSessionId: String, positionTicks: Int64, isPaused: Bool) async {
        await performPost(path: "Sessions/Playing/Progress", body: [
            "ItemId": itemId,
            "PlaySessionId": playSessionId,
            "PositionTicks": positionTicks,
            "IsPaused": isPaused,
            "CanSeek": true,
            "PlayMethod": "DirectStream"
        ])
    }

    /// Ends a play session at its final position — this is what lets Jellyfin update play count,
    /// last-played date, and (past its own completion threshold) mark the item played.
    func reportPlaybackStopped(itemId: String, playSessionId: String, positionTicks: Int64) async {
        await performPost(path: "Sessions/Playing/Stopped", body: [
            "ItemId": itemId,
            "PlaySessionId": playSessionId,
            "PositionTicks": positionTicks
        ])
    }

    func imageURL(itemId: String, imageType: String = "Primary", maxWidth: Int = 400) -> URL? {
        guard let serverURL, let accessToken else { return nil }
        var components = URLComponents(url: serverURL.appendingPathComponent("Items/\(itemId)/Images/\(imageType)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "maxWidth", value: String(maxWidth)),
            URLQueryItem(name: "api_key", value: accessToken)
        ]
        return components?.url
    }

    /// `maxBitrateKbps` of `nil` requests the original file untouched (`static=true`, no
    /// transcoding); any other value asks Jellyfin to transcode down to that bitrate instead.
    func streamURL(itemId: String, maxBitrateKbps: Int? = nil) -> URL? {
        guard let serverURL, let accessToken else { return nil }
        var components = URLComponents(url: serverURL.appendingPathComponent("Audio/\(itemId)/stream"), resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "api_key", value: accessToken)]
        if let maxBitrateKbps {
            queryItems.append(URLQueryItem(name: "static", value: "false"))
            queryItems.append(URLQueryItem(name: "audioBitRate", value: String(maxBitrateKbps * 1000)))
            queryItems.append(URLQueryItem(name: "audioCodec", value: "aac"))
        } else {
            queryItems.append(URLQueryItem(name: "static", value: "true"))
        }
        components?.queryItems = queryItems
        return components?.url
    }
}
