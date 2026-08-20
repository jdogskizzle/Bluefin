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

    var id: String { Id }

    enum CodingKeys: String, CodingKey {
        case Id, Name, CollectionType, AlbumArtist, Artists, Album, AlbumId, ProductionYear, RunTimeTicks, IndexNumber, ChildCount, ImageTags
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
}
