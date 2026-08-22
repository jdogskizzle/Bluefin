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
///
/// Also tracks which songs are currently in that pinned playlist (`pinnedSongIds`), so any song row
/// anywhere in the app can show a "this is in your pinned playlist" indicator without its own cache
/// lookup — kept in sync automatically whenever the pinned playlist changes, or its song list does
/// (e.g. adding/removing a song from it elsewhere), via `LibraryCacheChangeCenter`.
@MainActor
final class PinnedPlaylistStore: ObservableObject {
    static let shared = PinnedPlaylistStore()

    @Published private(set) var pinnedPlaylistId: String?
    @Published private(set) var pinnedPlaylistName: String?
    @Published private(set) var pinnedSongIds: Set<String> = []

    private static let idDefaultsKey = "com.bluefin.pinnedPlaylistId"
    private static let nameDefaultsKey = "com.bluefin.pinnedPlaylistName"

    private var changeSubscription: AnyCancellable?

    private init() {
        pinnedPlaylistId = UserDefaults.standard.string(forKey: Self.idDefaultsKey)
        pinnedPlaylistName = UserDefaults.standard.string(forKey: Self.nameDefaultsKey)

        changeSubscription = LibraryCacheChangeCenter.didChange
            .sink { [weak self] key in
                guard let self, let id = self.pinnedPlaylistId, key == "playlistSongs:\(id)" else { return }
                Task { await self.refreshPinnedSongIds() }
            }

        Task { await refreshPinnedSongIds() }
    }

    func isPinned(_ playlistId: String) -> Bool {
        pinnedPlaylistId == playlistId
    }

    func isSongPinned(_ songId: String) -> Bool {
        pinnedSongIds.contains(songId)
    }

    func togglePin(id: String, name: String) {
        if pinnedPlaylistId == id {
            unpin()
        } else {
            pinnedPlaylistId = id
            pinnedPlaylistName = name
            UserDefaults.standard.set(id, forKey: Self.idDefaultsKey)
            UserDefaults.standard.set(name, forKey: Self.nameDefaultsKey)
            Task { await refreshPinnedSongIds() }
        }
    }

    func unpin() {
        pinnedPlaylistId = nil
        pinnedPlaylistName = nil
        pinnedSongIds = []
        UserDefaults.standard.removeObject(forKey: Self.idDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.nameDefaultsKey)
    }

    private func refreshPinnedSongIds() async {
        guard let id = pinnedPlaylistId, let songs = await LibraryCache.shared.items(for: "playlistSongs:\(id)") else {
            pinnedSongIds = []
            return
        }
        pinnedSongIds = Set(songs.map(\.Id))
    }
}
