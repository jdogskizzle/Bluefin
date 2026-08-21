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

    @Published var cacheSizeBytes: Int64 = 0
    @Published var isClearingCache = false
    @Published var cacheLimitBytes: Int64 = CacheManager.cacheLimitBytes {
        didSet {
            guard cacheLimitBytes != oldValue else { return }
            CacheManager.cacheLimitBytes = cacheLimitBytes
        }
    }
    @Published var preCacheLookahead: Int = CacheManager.preCacheLookahead {
        didSet {
            guard preCacheLookahead != oldValue else { return }
            CacheManager.preCacheLookahead = preCacheLookahead
        }
    }

    var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: cacheSizeBytes, countStyle: .file)
    }

    private let apiClient: JellyfinAPIClient

    init(apiClient: JellyfinAPIClient) {
        self.apiClient = apiClient
    }

    func refreshCacheSize() async {
        cacheSizeBytes = await CacheManager.shared.totalCacheSizeBytes()
    }

    func clearCache() async {
        isClearingCache = true
        await CacheManager.shared.clearCache()
        await refreshCacheSize()
        isClearingCache = false
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
