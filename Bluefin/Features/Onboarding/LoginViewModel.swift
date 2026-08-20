//
//  LoginViewModel.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Foundation
import Combine

@MainActor
class LoginViewModel: ObservableObject {
    @Published var serverURLString: String = ""
    @Published var username: String = ""
    @Published var passwordString: String = ""
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var loginSuccess: Bool = false
    
    private let apiClient: JellyfinAPIClient
    
    init(apiClient: JellyfinAPIClient = .shared) {
        self.apiClient = apiClient
    }
    
    func login() async {
        guard !serverURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Server URL cannot be empty."
            return
        }
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Username cannot be empty."
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await apiClient.authenticate(
                urlString: serverURLString,
                username: username,
                secret: passwordString
            )
            loginSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

