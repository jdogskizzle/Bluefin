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
    @Published var librarySizeBytes: Int64 = 0
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

    var formattedLibrarySize: String {
        ByteCountFormatter.string(fromByteCount: librarySizeBytes, countStyle: .file)
    }

    private let apiClient: JellyfinAPIClient

    init(apiClient: JellyfinAPIClient) {
        self.apiClient = apiClient
    }

    func refreshCacheSize() async {
        cacheSizeBytes = await CacheManager.shared.totalCacheSizeBytes()
    }

    /// The synced library: cached metadata (`LibraryCache`), artwork (`ImageCache`), and lyrics —
    /// distinct from `cacheSizeBytes` (downloaded audio), and unaffected by `clearCache()`.
    func refreshLibrarySize() async {
        let metadataBytes = await LibraryCache.shared.totalCacheSizeBytes()
        let imageBytes = await ImageCache.shared.totalCacheSizeBytes()
        let lyricsBytes = await CacheManager.shared.totalLyricsSizeBytes()
        librarySizeBytes = metadataBytes + imageBytes + lyricsBytes
    }

    func clearCache() async {
        isClearingCache = true
        await CacheManager.shared.clearCache()
        await refreshCacheSize()
        isClearingCache = false
    }

    private static let librariesCacheKey = "musicLibraries"

    func loadLibraries() async {
        errorMessage = nil
        let cached = await LibraryCache.shared.items(for: Self.librariesCacheKey)
        if let cached {
            musicLibraries = cached
        } else {
            isLoading = true
        }

        do {
            let all = try await apiClient.fetchLibraries()
            let libraries = all.filter { $0.CollectionType == "music" }
            musicLibraries = libraries
            await LibraryCache.shared.store(libraries, for: Self.librariesCacheKey)
        } catch {
            if cached == nil {
                errorMessage = error.localizedDescription
            }
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
