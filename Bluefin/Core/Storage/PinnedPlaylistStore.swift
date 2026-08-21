//
//  PinnedPlaylistStore.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Combine
import Foundation

/// Tracks which single playlist (if any) is pinned — shown first in the Playlists list and
/// surfaced on Home. Only one playlist can be pinned at a time; pinning a new one replaces
/// whatever was pinned before.
@MainActor
final class PinnedPlaylistStore: ObservableObject {
    static let shared = PinnedPlaylistStore()

    @Published private(set) var pinnedPlaylistId: String?

    private static let defaultsKey = "com.bluefin.pinnedPlaylistId"

    private init() {
        pinnedPlaylistId = UserDefaults.standard.string(forKey: Self.defaultsKey)
    }

    func isPinned(_ playlistId: String) -> Bool {
        pinnedPlaylistId == playlistId
    }

    func togglePin(_ playlistId: String) {
        if pinnedPlaylistId == playlistId {
            pinnedPlaylistId = nil
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        } else {
            pinnedPlaylistId = playlistId
            UserDefaults.standard.set(playlistId, forKey: Self.defaultsKey)
        }
    }
}
