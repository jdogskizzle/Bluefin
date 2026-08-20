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
    
    private let clientName = "Bluefin"
    private let deviceName = "iOS Device"
    private let deviceId = "BluefinDevice123"
    private let version = "1.0.0"
    
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
    }
    
    func logout() {
        self.serverURL = nil
        self.accessToken = nil
        self.userId = nil
        self.isAuthorized = false
        
        KeychainHelper.shared.delete(service: "com.bluefin.app", account: "server_url")
        KeychainHelper.shared.delete(service: "com.bluefin.app", account: "access_token")
        KeychainHelper.shared.delete(service: "com.bluefin.app", account: "user_id")
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
}
