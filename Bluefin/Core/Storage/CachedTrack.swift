//
//  CachedTrack.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Foundation
import SwiftData

/// Local record of a Jellyfin track: its metadata for offline browsing, and
/// (once downloaded) where its audio file lives on disk. `fileSizeBytes` and
/// `lastAccessedDate` exist so the cache manager can enforce a size limit
/// with LRU eviction once that lands.
@Model
final class CachedTrack {
    @Attribute(.unique) var id: String
    var title: String
    var artistName: String
    var albumName: String
    var albumId: String?
    var durationTicks: Int64
    var localFilePath: String?
    var isDownloaded: Bool
    var fileSizeBytes: Int64?
    var lastAccessedDate: Date

    init(
        id: String,
        title: String,
        artistName: String,
        albumName: String,
        albumId: String? = nil,
        durationTicks: Int64,
        localFilePath: String? = nil,
        isDownloaded: Bool = false,
        fileSizeBytes: Int64? = nil,
        lastAccessedDate: Date = .now
    ) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.albumName = albumName
        self.albumId = albumId
        self.durationTicks = durationTicks
        self.localFilePath = localFilePath
        self.isDownloaded = isDownloaded
        self.fileSizeBytes = fileSizeBytes
        self.lastAccessedDate = lastAccessedDate
    }
}

extension CachedTrack {
    convenience init(item: BaseItemDto, localFilePath: String? = nil, isDownloaded: Bool = false, fileSizeBytes: Int64? = nil) {
        self.init(
            id: item.Id,
            title: item.Name,
            artistName: item.AlbumArtist ?? item.Artists?.first ?? "",
            albumName: item.Album ?? "",
            albumId: item.AlbumId,
            durationTicks: item.RunTimeTicks ?? 0,
            localFilePath: localFilePath,
            isDownloaded: isDownloaded,
            fileSizeBytes: fileSizeBytes
        )
    }
}
