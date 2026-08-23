//
//  DownloadsView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/22/26.
//

import SwiftUI

/// Everything currently downloaded, organized the way it was downloaded: an artist/album/playlist
/// downloaded as a whole (see `DownloadedGroup`) shows as just that one row, not every song inside
/// it — only songs downloaded individually (never part of a still-intact group) show under "Songs".
struct DownloadsView: View {
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var apiClient = JellyfinAPIClient.shared
    @State private var downloadedArtists: [BaseItemDto] = []
    @State private var downloadedAlbums: [BaseItemDto] = []
    @State private var downloadedPlaylists: [BaseItemDto] = []
    @State private var individualSongs: [BaseItemDto] = []

    private var isEmpty: Bool {
        downloadedArtists.isEmpty && downloadedAlbums.isEmpty && downloadedPlaylists.isEmpty && individualSongs.isEmpty
    }

    var body: some View {
        Group {
            if isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Download a song, album, artist, or playlist to see it here.")
                )
            } else {
                List {
                    if !downloadedArtists.isEmpty {
                        Section("Artists") {
                            ForEach(downloadedArtists) { artist in
                                LibraryNavigableRow(item: artist)
                            }
                        }
                    }
                    if !downloadedAlbums.isEmpty {
                        Section("Albums") {
                            ForEach(downloadedAlbums) { album in
                                LibraryNavigableRow(item: album)
                            }
                        }
                    }
                    if !downloadedPlaylists.isEmpty {
                        Section("Playlists") {
                            ForEach(downloadedPlaylists) { playlist in
                                LibraryNavigableRow(item: playlist)
                            }
                        }
                    }
                    if !individualSongs.isEmpty {
                        Section("Songs") {
                            ForEach(individualSongs) { song in
                                LibraryNavigableRow(item: song) {
                                    let index = individualSongs.firstIndex(of: song) ?? 0
                                    AudioPlayerManager.shared.play(queue: individualSongs, startAt: index)
                                }
                                .songActions(for: song)
                            }
                        }
                    }
                }
                .avoidsMiniPlayer()
            }
        }
        .navigationTitle("Downloads")
        .task(id: downloadManager.downloadedItemIds) {
            await reload()
        }
        .task(id: downloadManager.downloadedGroups.map(\.id)) {
            await reload()
        }
    }

    private func reload() async {
        guard let libraryId = apiClient.selectedLibraryId else {
            downloadedArtists = []
            downloadedAlbums = []
            downloadedPlaylists = []
            individualSongs = []
            return
        }

        let groups = downloadManager.downloadedGroups
        let coveredSongIds = groups.reduce(into: Set<String>()) { $0.formUnion($1.songIds) }

        let artists = await LibraryCache.shared.items(for: "artists:\(libraryId)") ?? []
        let albums = await LibraryCache.shared.items(for: "albums:\(libraryId)") ?? []
        let playlists = await LibraryCache.shared.items(for: "playlists") ?? []
        let songs = await LibraryCache.shared.items(for: "songs:\(libraryId)") ?? []

        downloadedArtists = groups.filter { $0.kind == .artist }.compactMap { group in artists.first { $0.Id == group.id } }
        downloadedAlbums = groups.filter { $0.kind == .album }.compactMap { group in albums.first { $0.Id == group.id } }
        downloadedPlaylists = groups.filter { $0.kind == .playlist }.compactMap { group in playlists.first { $0.Id == group.id } }

        let downloadedIds = downloadManager.downloadedItemIds
        individualSongs = songs.filter { downloadedIds.contains($0.Id) && !coveredSongIds.contains($0.Id) }
    }
}
