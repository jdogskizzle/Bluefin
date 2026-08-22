//
//  FavoritesStore.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/22/26.
//

import Combine
import Foundation

/// Tracks which songs are favorited on the Jellyfin server, so the Now Playing heart button and
/// the Library "Favorites" section can both reflect it reactively. Seeded from the synced song
/// list's `UserData.IsFavorite` (refreshed after every sync), then kept current with optimistic
/// local updates whenever the user toggles a favorite — reverted if the server call fails.
@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var favoriteSongIds: Set<String> = []

    private init() {
        Task { await refreshFromSync() }
    }

    func isFavorite(_ songId: String) -> Bool {
        favoriteSongIds.contains(songId)
    }

    func refreshFromSync() async {
        guard let libraryId = JellyfinAPIClient.shared.selectedLibraryId,
              let songs = await LibraryCache.shared.items(for: "songs:\(libraryId)") else {
            return
        }
        favoriteSongIds = Set(songs.filter { $0.UserData?.IsFavorite == true }.map(\.Id))
    }

    func toggleFavorite(_ song: BaseItemDto) {
        let wasFavorite = favoriteSongIds.contains(song.Id)
        if wasFavorite {
            favoriteSongIds.remove(song.Id)
        } else {
            favoriteSongIds.insert(song.Id)
        }

        Task {
            do {
                if wasFavorite {
                    try await JellyfinAPIClient.shared.unmarkFavorite(itemId: song.Id)
                } else {
                    try await JellyfinAPIClient.shared.markFavorite(itemId: song.Id)
                }
            } catch {
                if wasFavorite {
                    favoriteSongIds.insert(song.Id)
                } else {
                    favoriteSongIds.remove(song.Id)
                }
            }
        }
    }
}
