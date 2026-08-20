//
//  SettingsViewModel.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var musicLibraries: [BaseItemDto] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiClient: JellyfinAPIClient

    init(apiClient: JellyfinAPIClient) {
        self.apiClient = apiClient
    }

    func loadLibraries() async {
        isLoading = true
        errorMessage = nil
        do {
            let all = try await apiClient.fetchLibraries()
            musicLibraries = all.filter { $0.CollectionType == "music" }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func select(_ library: BaseItemDto) {
        apiClient.setSelectedLibrary(library.Id)
    }

    func signOut() {
        apiClient.logout()
    }
}
