//
//  PinnedPlaylistStore.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Combine
import Foundation

/// Tracks which single playlist (if any) is pinned — shown first in the Playlists list, surfaced
/// on Home, and offered as a one-tap "Add to <name>" target from any song's context menu. Only one
/// playlist can be pinned at a time; pinning a new one replaces whatever was pinned before. Stores
/// the name alongside the id so "Add to <name>" doesn't need an async lookup to display.
@MainActor
final class PinnedPlaylistStore: ObservableObject {
    static let shared = PinnedPlaylistStore()

    @Published private(set) var pinnedPlaylistId: String?
    @Published private(set) var pinnedPlaylistName: String?

    private static let idDefaultsKey = "com.bluefin.pinnedPlaylistId"
    private static let nameDefaultsKey = "com.bluefin.pinnedPlaylistName"

    private init() {
        pinnedPlaylistId = UserDefaults.standard.string(forKey: Self.idDefaultsKey)
        pinnedPlaylistName = UserDefaults.standard.string(forKey: Self.nameDefaultsKey)
    }

    func isPinned(_ playlistId: String) -> Bool {
        pinnedPlaylistId == playlistId
    }

    func togglePin(id: String, name: String) {
        if pinnedPlaylistId == id {
            unpin()
        } else {
            pinnedPlaylistId = id
            pinnedPlaylistName = name
            UserDefaults.standard.set(id, forKey: Self.idDefaultsKey)
            UserDefaults.standard.set(name, forKey: Self.nameDefaultsKey)
        }
    }

    func unpin() {
        pinnedPlaylistId = nil
        pinnedPlaylistName = nil
        UserDefaults.standard.removeObject(forKey: Self.idDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.nameDefaultsKey)
    }
}
