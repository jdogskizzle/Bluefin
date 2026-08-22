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
    @State private var pinnedPlaylist: BaseItemDto?
    @State private var pinnedPlaylistSongs: [BaseItemDto] = []
    @State private var upcomingReleases: [LidarrCalendarItem] = []

    var body: some View {
        NavigationStack(path: $navigator.homePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !upcomingReleases.isEmpty {
                        upcomingReleasesSection
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
            await loadUpcomingReleases()
        }
        .onReceive(LibraryCacheChangeCenter.didChange) { key in
            guard let id = pinnedStore.pinnedPlaylistId, key == "playlists" || key == "playlistSongs:\(id)" else { return }
            Task { await loadPinnedPlaylist() }
        }
    }

    private func loadUpcomingReleases() async {
        guard lidarrClient.isConnected else {
            upcomingReleases = []
            return
        }
        upcomingReleases = (try? await lidarrClient.fetchUpcomingReleases()) ?? []
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

    private var upcomingReleasesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Upcoming Releases")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(upcomingReleases) { release in
                        upcomingReleaseCard(release)
                    }
                }
            }
        }
    }

    private func upcomingReleaseCard(_ release: LidarrCalendarItem) -> some View {
        NavigationLink(value: release) {
            VStack(alignment: .leading, spacing: 4) {
                AsyncImage(url: release.coverImageURL(serverURL: lidarrClient.serverURL, apiKey: lidarrClient.apiKey)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.15))
                            .overlay(Image(systemName: "opticaldisc").foregroundStyle(.secondary))
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(release.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(release.artistName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let releaseDate = release.releaseDate {
                    Text(releaseDate.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120)
        }
        .buttonStyle(.plain)
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
