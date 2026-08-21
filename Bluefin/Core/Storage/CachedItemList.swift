//
//  CachedItemList.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Foundation
import SwiftData

/// The last known-good result of a library query (e.g. "albums in library X", "songs on album Y"),
/// keyed by a string the caller derives from the query's parameters. Storing the raw JSON-encoded
/// `[BaseItemDto]` rather than a relational schema keeps this in lockstep with the API's shape and
/// covers every current query (artists/albums/songs/playlists, artist's albums, album's songs,
/// playlist's songs) without needing to model relationships Jellyfin itself doesn't expose to us
/// (e.g. albums only carry an artist *name*, not an artist id).
@Model
final class CachedItemList {
    @Attribute(.unique) var key: String
    var itemsData: Data
    var updatedAt: Date

    init(key: String, itemsData: Data, updatedAt: Date = .now) {
        self.key = key
        self.itemsData = itemsData
        self.updatedAt = updatedAt
    }
}
