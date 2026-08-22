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
    @ObservedObject private var apiClient = JellyfinAPIClient.shared
    @State private var pinnedPlaylist: BaseItemDto?
    @State private var pinnedPlaylistSongs: [BaseItemDto] = []
    @State private var randomAlbum: BaseItemDto?

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

                    if let randomAlbum {
                        randomAlbumSection(for: randomAlbum)
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
        .task {
            await randomizeAlbum()
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

    /// Picked once per app launch (this `.task` fires once, the first time `HomeView` appears) —
    /// the "shuffle" button on the card itself is the only other way to get a new pick.
    private func randomizeAlbum() async {
        guard let libraryId = apiClient.selectedLibraryId,
              let albums = await LibraryCache.shared.items(for: "albums:\(libraryId)") else {
            randomAlbum = nil
            return
        }
        randomAlbum = albums.randomElement()
    }

    private func randomAlbumSection(for album: BaseItemDto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Random Album")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await randomizeAlbum() }
                } label: {
                    Image(systemName: "shuffle")
                }
            }

            HStack(spacing: 12) {
                NavigationLink(value: LibraryRoute.albumSongs(album)) {
                    HStack(spacing: 12) {
                        CachedAsyncImage(itemId: album.Id) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.15))
                                .overlay(Image(systemName: "square.stack").foregroundStyle(.secondary))
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(album.Name)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if let artist = album.AlbumArtist {
                                Text(artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    Task { await play(album) }
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contextMenu {
                Button {
                    Task { await addToQueue(album) }
                } label: {
                    Label("Add to Queue", systemImage: "text.insert")
                }
            }
        }
    }

    private func play(_ album: BaseItemDto) async {
        guard let songs = await LibraryCache.shared.items(for: "albumSongs:\(album.Id)") else { return }
        AudioPlayerManager.shared.play(queue: songs, startAt: 0)
    }

    private func addToQueue(_ album: BaseItemDto) async {
        guard let songs = await LibraryCache.shared.items(for: "albumSongs:\(album.Id)") else { return }
        AudioPlayerManager.shared.addToSubqueue(songs)
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
