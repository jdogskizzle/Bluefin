//
//  DownloadsView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/22/26.
//

import SwiftUI

/// Every song currently downloaded, across all albums/artists/playlists — filters the synced
/// "songs" list (the same source every other Library screen reads from) down to whatever
/// `DownloadManager` currently reports as downloaded, rather than reconstructing song metadata
/// from `CachedTrack` itself.
struct DownloadsView: View {
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var apiClient = JellyfinAPIClient.shared
    @State private var downloadedSongs: [BaseItemDto] = []

    var body: some View {
        Group {
            if downloadedSongs.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Download a song, album, artist, or playlist to see it here.")
                )
            } else {
                List(downloadedSongs) { song in
                    LibraryNavigableRow(item: song) {
                        let index = downloadedSongs.firstIndex(of: song) ?? 0
                        AudioPlayerManager.shared.play(queue: downloadedSongs, startAt: index)
                    }
                    .songActions(for: song)
                }
                .avoidsMiniPlayer()
            }
        }
        .navigationTitle("Downloads")
        .task(id: downloadManager.downloadedItemIds) {
            await loadDownloadedSongs()
        }
    }

    private func loadDownloadedSongs() async {
        guard let libraryId = apiClient.selectedLibraryId,
              let songs = await LibraryCache.shared.items(for: "songs:\(libraryId)") else {
            downloadedSongs = []
            return
        }
        let ids = downloadManager.downloadedItemIds
        downloadedSongs = songs.filter { ids.contains($0.Id) }
    }
}
