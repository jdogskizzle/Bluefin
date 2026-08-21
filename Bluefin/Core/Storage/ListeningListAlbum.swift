//
//  ListeningListAlbum.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Foundation
import SwiftData

/// An album the user has saved to listen to later, shown in the Home view's "Listen List".
@Model
final class ListeningListAlbum {
    @Attribute(.unique) var albumId: String
    var title: String
    var artist: String
    var addedAt: Date

    init(albumId: String, title: String, artist: String, addedAt: Date = .now) {
        self.albumId = albumId
        self.title = title
        self.artist = artist
        self.addedAt = addedAt
    }
}

extension ListeningListAlbum {
    convenience init(item: BaseItemDto, addedAt: Date = .now) {
        self.init(
            albumId: item.Id,
            title: item.Name,
            artist: item.AlbumArtist ?? item.Artists?.first ?? "",
            addedAt: addedAt
        )
    }
}
