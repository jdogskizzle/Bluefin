//
//  LibraryRoute.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Foundation

enum LibraryRoute: Hashable {
    case artists
    case albums
    case songs
    case playlists
    case artistAlbums(BaseItemDto)
    case albumSongs(BaseItemDto)
    case playlistSongs(BaseItemDto)
}
