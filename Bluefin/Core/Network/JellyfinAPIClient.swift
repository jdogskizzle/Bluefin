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
    private let deviceId = "BluefinDevice123"
    private let version = "1.0.0"
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
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw JellyfinError.invalidResponse
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
        sortBy: String = "SortName"
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

        let response: ItemsResponse = try await performGet(path: "Users/\(userId)/Items", queryItems: queryItems)
        return response.Items
    }

    func fetchPlaylistItems(playlistId: String) async throws -> [BaseItemDto] {
        guard let userId else { throw JellyfinError.invalidResponse }
        let response: ItemsResponse = try await performGet(
            path: "Playlists/\(playlistId)/Items",
            queryItems: [URLQueryItem(name: "userId", value: userId)]
        )
        return response.Items
    }

    func imageURL(itemId: String, maxWidth: Int = 400) -> URL? {
        guard let serverURL, let accessToken else { return nil }
        var components = URLComponents(url: serverURL.appendingPathComponent("Items/\(itemId)/Images/Primary"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "maxWidth", value: String(maxWidth)),
            URLQueryItem(name: "api_key", value: accessToken)
        ]
        return components?.url
    }
}
