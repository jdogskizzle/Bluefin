//
//  LibraryCache.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Combine
import Foundation
import SwiftData

/// Persists the result of each library query (artists, albums, songs, playlists, an artist's
/// albums, an album's or playlist's songs) so browsing works instantly from local data and keeps
/// working with no network at all, rather than requiring a round trip to Jellyfin every time a
/// list screen appears.
@ModelActor
actor LibraryCache {
    static let shared = LibraryCache(modelContainer: Persistence.shared)

    func items(for key: String) -> [BaseItemDto]? {
        let descriptor = FetchDescriptor<CachedItemList>(predicate: #Predicate { $0.key == key })
        guard let entry = try? modelContext.fetch(descriptor).first else { return nil }
        return try? JSONDecoder().decode([BaseItemDto].self, from: entry.itemsData)
    }

    func store(_ items: [BaseItemDto], for key: String) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        let descriptor = FetchDescriptor<CachedItemList>(predicate: #Predicate { $0.key == key })
        if let entry = try? modelContext.fetch(descriptor).first {
            entry.itemsData = data
            entry.updatedAt = .now
        } else {
            modelContext.insert(CachedItemList(key: key, itemsData: data))
        }
        try? modelContext.save()

        Task { @MainActor in
            LibraryCacheChangeCenter.didChange.send(key)
        }
    }

    func totalCacheSizeBytes() -> Int64 {
        let descriptor = FetchDescriptor<CachedItemList>()
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        return entries.reduce(Int64(0)) { $0 + Int64($1.itemsData.count) }
    }
}
