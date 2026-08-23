//
//  DownloadedGroup.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/22/26.
//

import Foundation
import SwiftData

/// Records that a whole artist/album/playlist was downloaded as a unit, so the Library "Downloads"
/// section can show just that one artist/album/playlist instead of every song inside it — a group
/// is only considered valid while every song in `songIds` is still downloaded; removing any one of
/// them (even individually) invalidates the whole group (see `DownloadStore.removeSongFromGroups`).
@Model
final class DownloadedGroup {
    @Attribute(.unique) var id: String
    /// Raw value of `DownloadedGroupKind` ("artist"/"album"/"playlist").
    var kind: String
    var name: String
    var songIds: [String]

    init(id: String, kind: String, name: String, songIds: [String]) {
        self.id = id
        self.kind = kind
        self.name = name
        self.songIds = songIds
    }
}
