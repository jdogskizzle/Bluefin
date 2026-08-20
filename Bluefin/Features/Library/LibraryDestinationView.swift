//
//  LibraryDestinationView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import SwiftUI

struct LibraryDestinationView: View {
    let route: LibraryRoute
    @ObservedObject private var apiClient = JellyfinAPIClient.shared

    var body: some View {
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
