//
//  FavoritesView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/22/26.
//

import SwiftUI

/// Every song favorited on the Jellyfin server — filters the synced "songs" list down to whatever
/// `FavoritesStore` currently reports as favorited.
struct FavoritesView: View {
    @ObservedObject private var favoritesStore = FavoritesStore.shared
    @ObservedObject private var apiClient = JellyfinAPIClient.shared
    @State private var favoriteSongs: [BaseItemDto] = []

    var body: some View {
        Group {
            if favoriteSongs.isEmpty {
                ContentUnavailableView(
                    "No Favorites",
                    systemImage: "heart",
                    description: Text("Tap the heart on Now Playing to favorite a song.")
                )
            } else {
                List(favoriteSongs) { song in
                    LibraryNavigableRow(item: song) {
                        let index = favoriteSongs.firstIndex(of: song) ?? 0
                        AudioPlayerManager.shared.play(queue: favoriteSongs, startAt: index)
                    }
                    .songActions(for: song)
                }
                .avoidsMiniPlayer()
            }
        }
        .navigationTitle("Favorites")
        .task(id: favoritesStore.favoriteSongIds) {
            await loadFavoriteSongs()
        }
    }

    private func loadFavoriteSongs() async {
        guard let libraryId = apiClient.selectedLibraryId,
              let songs = await LibraryCache.shared.items(for: "songs:\(libraryId)") else {
            favoriteSongs = []
            return
        }
        let ids = favoritesStore.favoriteSongIds
        favoriteSongs = songs.filter { ids.contains($0.Id) }
    }
}
