//
//  LibraryNavigableRow.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import SwiftUI

struct LibraryNavigableRow: View {
    let item: BaseItemDto
    var isPinned: Bool = false
    var onPlaySong: (() -> Void)? = nil

    var body: some View {
        if let route = LibraryNavigableRow.route(for: item) {
            NavigationLink(value: route) {
                LibraryItemRow(item: item, isPinned: isPinned)
            }
        } else if item.ItemType == "Audio", let onPlaySong {
            Button(action: onPlaySong) {
                LibraryItemRow(item: item, isPinned: isPinned)
            }
            .buttonStyle(.plain)
        } else {
            LibraryItemRow(item: item, isPinned: isPinned)
        }
    }

    static func route(for item: BaseItemDto) -> LibraryRoute? {
        switch item.ItemType {
        case "MusicArtist": return .artistAlbums(item)
        case "MusicAlbum": return .albumSongs(item)
        case "Playlist": return .playlistSongs(item)
        case "MusicGenre": return .genreAlbums(item)
        default: return nil
        }
    }
}
