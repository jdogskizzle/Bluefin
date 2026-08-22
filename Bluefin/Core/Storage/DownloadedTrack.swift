//
//  DownloadedTrack.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/22/26.
//

import Foundation
import SwiftData

/// A track the user explicitly downloaded — entirely separate storage from `CachedTrack`'s
/// opportunistic pre-cache. Its file lives under Application Support (not Caches), so it's never
/// evicted by `CacheManager`'s size limit and isn't reclaimable by the OS the way cache-directory
/// content is; it's removed only when the user removes it themselves.
@Model
final class DownloadedTrack {
    @Attribute(.unique) var id: String
    var title: String
    var artistName: String
    var albumName: String
    var albumId: String?
    var durationTicks: Int64
    var localFilePath: String
    var fileSizeBytes: Int64
    var downloadedDate: Date

    init(
        id: String,
        title: String,
        artistName: String,
        albumName: String,
        albumId: String? = nil,
        durationTicks: Int64,
        localFilePath: String,
        fileSizeBytes: Int64,
        downloadedDate: Date = .now
    ) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.albumName = albumName
        self.albumId = albumId
        self.durationTicks = durationTicks
        self.localFilePath = localFilePath
        self.fileSizeBytes = fileSizeBytes
        self.downloadedDate = downloadedDate
    }
}

extension DownloadedTrack {
    convenience init(item: BaseItemDto, localFilePath: String, fileSizeBytes: Int64) {
        self.init(
            id: item.Id,
            title: item.Name,
            artistName: item.AlbumArtist ?? item.Artists?.first ?? "",
            albumName: item.Album ?? "",
            albumId: item.AlbumId,
            durationTicks: item.RunTimeTicks ?? 0,
            localFilePath: localFilePath,
            fileSizeBytes: fileSizeBytes
        )
    }
}
