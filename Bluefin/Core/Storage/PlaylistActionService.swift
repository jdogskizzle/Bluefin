//
//  PlaylistActionService.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Foundation

/// Adds a song to a playlist without blocking the caller: fires the request in the background and
/// reports success/failure via `ToastCenter` once the server actually confirms it (the request has
/// its own 10s timeout, set on `JellyfinAPIClient.addItemToPlaylist`, so a hung server surfaces as a
/// failure toast rather than hanging indefinitely). On success, also appends the song to the
/// locally cached `playlistSongs:<id>` list, and bumps the playlist's own cached `ChildCount` (its
/// track count, shown wherever the playlist itself is listed) — both so the change is reflected
/// immediately without waiting for the next full library sync.
enum PlaylistActionService {
    static func addSong(_ song: BaseItemDto, toPlaylistId playlistId: String, playlistName: String) {
        Task {
            do {
                try await JellyfinAPIClient.shared.addItemToPlaylist(playlistId: playlistId, itemId: song.Id)
                let added = await appendToCachedPlaylist(song, playlistId: playlistId)
                if added {
                    await bumpPlaylistChildCount(playlistId: playlistId, by: 1)
                }
                ToastCenter.shared.show("Added to \(playlistName)")
            } catch {
                ToastCenter.shared.show("Couldn't add to \(playlistName)", isError: true)
            }
        }
    }

    /// `song.PlaylistItemId` (this specific occurrence within the playlist) is used when present;
    /// falls back to `song.Id` for a server response that didn't include it, on the assumption
    /// that's still better than refusing to try — a genuine failure just surfaces as an error toast.
    static func removeSong(_ song: BaseItemDto, fromPlaylistId playlistId: String, playlistName: String) {
        let entryId = song.PlaylistItemId ?? song.Id
        Task {
            do {
                try await JellyfinAPIClient.shared.removeItemFromPlaylist(playlistId: playlistId, entryId: entryId)
                let removed = await removeFromCachedPlaylist(song, playlistId: playlistId)
                if removed {
                    await bumpPlaylistChildCount(playlistId: playlistId, by: -1)
                }
                ToastCenter.shared.show("Removed from \(playlistName)")
            } catch {
                ToastCenter.shared.show("Couldn't remove from \(playlistName)", isError: true)
            }
        }
    }

    @discardableResult
    private static func appendToCachedPlaylist(_ song: BaseItemDto, playlistId: String) async -> Bool {
        let key = "playlistSongs:\(playlistId)"
        var items = await LibraryCache.shared.items(for: key) ?? []
        guard !items.contains(where: { $0.Id == song.Id }) else { return false }
        items.append(song)
        await LibraryCache.shared.store(items, for: key)
        return true
    }

    @discardableResult
    private static func removeFromCachedPlaylist(_ song: BaseItemDto, playlistId: String) async -> Bool {
        let key = "playlistSongs:\(playlistId)"
        guard var items = await LibraryCache.shared.items(for: key) else { return false }
        let originalCount = items.count
        if let entryId = song.PlaylistItemId {
            items.removeAll { $0.PlaylistItemId == entryId }
        } else {
            items.removeAll { $0.Id == song.Id }
        }
        guard items.count != originalCount else { return false }
        await LibraryCache.shared.store(items, for: key)
        return true
    }

    private static func bumpPlaylistChildCount(playlistId: String, by delta: Int) async {
        guard var playlists = await LibraryCache.shared.items(for: "playlists"),
              let index = playlists.firstIndex(where: { $0.Id == playlistId }) else { return }
        let newCount = max(0, (playlists[index].ChildCount ?? 0) + delta)
        playlists[index] = playlists[index].withChildCount(newCount)
        await LibraryCache.shared.store(playlists, for: "playlists")
    }
}
