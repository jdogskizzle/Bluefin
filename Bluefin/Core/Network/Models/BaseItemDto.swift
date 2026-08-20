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
    let ProductionYear: Int?
    let RunTimeTicks: Int64?
    let IndexNumber: Int?
    let ChildCount: Int?
    let ImageTags: [String: String]?

    var id: String { Id }

    enum CodingKeys: String, CodingKey {
        case Id, Name, CollectionType, AlbumArtist, Artists, Album, ProductionYear, RunTimeTicks, IndexNumber, ChildCount, ImageTags
        case ItemType = "Type"
    }
}
