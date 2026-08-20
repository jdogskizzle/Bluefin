//
//  LibraryView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import SwiftUI

struct LibraryView: View {
    @ObservedObject private var apiClient = JellyfinAPIClient.shared

    var body: some View {
        NavigationStack {
            Group {
                if apiClient.selectedLibraryId == nil {
                    ContentUnavailableView(
                        "No Music Library Selected",
                        systemImage: "music.note.list",
                        description: Text("Choose a music library in Settings to start browsing.")
                    )
                } else {
                    List {
                        NavigationLink(value: LibraryRoute.artists) {
                            Label("Artists", systemImage: "music.mic")
                        }
                        NavigationLink(value: LibraryRoute.albums) {
                            Label("Albums", systemImage: "square.stack")
                        }
                        NavigationLink(value: LibraryRoute.songs) {
                            Label("Songs", systemImage: "music.note")
                        }
                        NavigationLink(value: LibraryRoute.playlists) {
                            Label("Playlists", systemImage: "music.note.list")
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: LibraryRoute.self) { route in
                destinationView(for: route)
            }
        }
    }

    @ViewBuilder
    private func destinationView(for route: LibraryRoute) -> some View {
        switch route {
        case .artists:
            LibraryListView(title: "Artists", itemType: .artist) {
                try await JellyfinAPIClient.shared.fetchItems(
                    parentId: apiClient.selectedLibraryId,
                    includeItemTypes: "MusicArtist"
                )
            }
        case .albums:
            LibraryListView(title: "Albums", itemType: .album) {
                try await JellyfinAPIClient.shared.fetchItems(
                    parentId: apiClient.selectedLibraryId,
                    includeItemTypes: "MusicAlbum"
                )
            }
        case .songs:
            LibraryListView(title: "Songs", itemType: .song) {
                try await JellyfinAPIClient.shared.fetchItems(
                    parentId: apiClient.selectedLibraryId,
                    includeItemTypes: "Audio"
                )
            }
        case .playlists:
            LibraryListView(title: "Playlists", itemType: .playlist) {
                try await JellyfinAPIClient.shared.fetchItems(
                    includeItemTypes: "Playlist",
                    mediaTypes: "Audio"
                )
            }
        case .artistAlbums(let artist):
            LibraryListView(title: artist.Name, itemType: .album) {
                try await JellyfinAPIClient.shared.fetchItems(
                    parentId: apiClient.selectedLibraryId,
                    includeItemTypes: "MusicAlbum",
                    artistIds: artist.Id
                )
            }
        case .albumSongs(let album):
            LibraryListView(title: album.Name, itemType: .song) {
                try await JellyfinAPIClient.shared.fetchItems(
                    parentId: album.Id,
                    includeItemTypes: "Audio",
                    recursive: false,
                    sortBy: "IndexNumber"
                )
            }
        case .playlistSongs(let playlist):
            LibraryListView(title: playlist.Name, itemType: .song) {
                try await JellyfinAPIClient.shared.fetchPlaylistItems(playlistId: playlist.Id)
            }
        }
    }
}

struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
    }
}
