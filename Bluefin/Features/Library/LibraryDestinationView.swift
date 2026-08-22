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
            ArtistListView(cacheKey: "artists:\(apiClient.selectedLibraryId ?? "")")
        case .albums:
            AlbumGridView(title: "Albums", subtitle: .artist, cacheKey: "albums:\(apiClient.selectedLibraryId ?? "")")
        case .songs:
            LibraryListView(title: "Songs", itemType: .song, cacheKey: "songs:\(apiClient.selectedLibraryId ?? "")")
        case .playlists:
            LibraryListView(title: "Playlists", itemType: .playlist, cacheKey: "playlists")
        case .downloads:
            DownloadsView()
        case .favorites:
            FavoritesView()
        case .artistAlbums(let artist):
            AlbumGridView(title: artist.Name, subtitle: .year, bannerItemId: artist.Id, cacheKey: "artistAlbums:\(artist.Id)")
        case .albumSongs(let album):
            AlbumDetailView(album: album)
        case .playlistSongs(let playlist):
            PlaylistDetailView(playlist: playlist)
        }
    }
}
