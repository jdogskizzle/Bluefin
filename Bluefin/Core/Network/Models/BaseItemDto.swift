//
//  BaseItemDto.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Foundation

struct ItemsResponse: Codable {
    let Items: [BaseItemDto]
    let TotalRecordCount: Int
}

struct BaseItemDto: Codable, Identifiable, Hashable {
    let Id: String
    let Name: String
    let ItemType: String
    let CollectionType: String?
    let AlbumArtist: String?
    let Artists: [String]?
    let Album: String?
    let AlbumId: String?
    let ProductionYear: Int?
    let RunTimeTicks: Int64?
    let IndexNumber: Int?
    let ChildCount: Int?
    let ImageTags: [String: String]?
    /// Only present when fetched as part of a playlist's items — identifies this specific entry
    /// within that playlist (distinct from `Id`, the underlying song's own item id), since Jellyfin
    /// allows the same song to appear in a playlist more than once. Needed to remove the correct
    /// occurrence rather than just "a" copy of the song.
    let PlaylistItemId: String?

    var id: String { Id }

    enum CodingKeys: String, CodingKey {
        case Id, Name, CollectionType, AlbumArtist, Artists, Album, AlbumId, ProductionYear, RunTimeTicks, IndexNumber, ChildCount, ImageTags, PlaylistItemId
        case ItemType = "Type"
    }
}

extension BaseItemDto {
    var formattedDuration: String? {
        guard let ticks = RunTimeTicks else { return nil }
        let totalSeconds = Int(ticks / 10_000_000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// The item id to request artwork for — songs have no art of their own, so this
    /// resolves to their album's art instead.
    var artworkItemId: String {
        if ItemType == "Audio", let albumId = AlbumId {
            return albumId
        }
        return Id
    }

    /// A copy with a different `ChildCount` — used to keep a playlist's own cached record (its
    /// track count) in step immediately after adding/removing a song, without waiting for the next
    /// full library sync to refetch it from the server.
    func withChildCount(_ newChildCount: Int) -> BaseItemDto {
        BaseItemDto(
            Id: Id, Name: Name, ItemType: ItemType, CollectionType: CollectionType,
            AlbumArtist: AlbumArtist, Artists: Artists, Album: Album, AlbumId: AlbumId,
            ProductionYear: ProductionYear, RunTimeTicks: RunTimeTicks, IndexNumber: IndexNumber,
            ChildCount: newChildCount, ImageTags: ImageTags, PlaylistItemId: PlaylistItemId
        )
    }
}
