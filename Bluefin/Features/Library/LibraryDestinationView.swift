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

    /// Albums crediting more contributing artists than this are treated as "various artists"
    /// compilations and excluded from an individual artist's album grid.
    private let variousArtistsThreshold = 10

    var body: some View {
        switch route {
        case .artists:
            ArtistListView {
                try await JellyfinAPIClient.shared.fetchItems(
                    parentId: apiClient.selectedLibraryId,
                    includeItemTypes: "MusicArtist"
                )
            }
        case .albums:
            AlbumGridView(title: "Albums", subtitle: .artist) {
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
            AlbumGridView(title: artist.Name, subtitle: .year) {
                let albums = try await JellyfinAPIClient.shared.fetchItems(
                    parentId: apiClient.selectedLibraryId,
                    includeItemTypes: "MusicAlbum",
                    artistIds: artist.Id,
                    sortBy: "PremiereDate"
                )
                return albums.filter { ($0.Artists?.count ?? 0) <= variousArtistsThreshold }
            }
        case .albumSongs(let album):
            AlbumDetailView(album: album)
        case .playlistSongs(let playlist):
            LibraryListView(title: playlist.Name, itemType: .song) {
                try await JellyfinAPIClient.shared.fetchPlaylistItems(playlistId: playlist.Id)
            }
        }
    }
}
