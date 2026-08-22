//
//  HomeView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Combine
import SwiftUI

struct HomeView: View {
    @ObservedObject private var pinnedStore = PinnedPlaylistStore.shared
    @ObservedObject private var navigator = AppNavigator.shared
    @ObservedObject private var lidarrClient = LidarrAPIClient.shared
    @ObservedObject private var releaseCache = LidarrReleaseCache.shared
    @State private var pinnedPlaylist: BaseItemDto?
    @State private var pinnedPlaylistSongs: [BaseItemDto] = []

    var body: some View {
        NavigationStack(path: $navigator.homePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !releaseCache.upcomingReleases.isEmpty {
                        LidarrUpcomingReleasesSection(title: "Upcoming Releases", releases: releaseCache.upcomingReleases)
                    }

                    if let pinnedPlaylist {
                        pinnedSection(for: pinnedPlaylist)
                    } else {
                        ContentUnavailableView(
                            "No Pinned Playlist",
                            systemImage: "pin",
                            description: Text("Long-press a playlist in Library to pin it here.")
                        )
                        .padding(.top, 80)
                    }
                }
                .padding()
                .avoidsMiniPlayer()
            }
            .navigationTitle("Home")
            .navigationDestination(for: LibraryRoute.self) { route in
                LibraryDestinationView(route: route)
            }
            .navigationDestination(for: LidarrCalendarItem.self) { release in
                LidarrAlbumDetailView(release: release)
            }
        }
        .task(id: pinnedStore.pinnedPlaylistId) {
            await loadPinnedPlaylist()
        }
        .task(id: lidarrClient.isConnected) {
            await releaseCache.refresh()
        }
        .onReceive(LibraryCacheChangeCenter.didChange) { key in
            guard let id = pinnedStore.pinnedPlaylistId, key == "playlists" || key == "playlistSongs:\(id)" else { return }
            Task { await loadPinnedPlaylist() }
        }
    }

    private func loadPinnedPlaylist() async {
        guard let id = pinnedStore.pinnedPlaylistId else {
            pinnedPlaylist = nil
            pinnedPlaylistSongs = []
            return
        }
        let playlists = await LibraryCache.shared.items(for: "playlists") ?? []
        pinnedPlaylist = playlists.first { $0.Id == id }
        pinnedPlaylistSongs = await LibraryCache.shared.items(for: "playlistSongs:\(id)") ?? []
    }

    private func pinnedSection(for playlist: BaseItemDto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pinned Playlist")
                .font(.headline)

            NavigationLink(value: LibraryRoute.playlistSongs(playlist)) {
                HStack(spacing: 12) {
                    CachedAsyncImage(itemId: playlist.Id) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.15))
                            .overlay(Image(systemName: "music.note.list").foregroundStyle(.secondary))
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(playlist.Name)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(playlist.ChildCount ?? 0) songs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            PlayShuffleBar(songs: pinnedPlaylistSongs)
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
