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

    /// Bulk counterpart to `removeSong`, for the playlist editor's multi-select delete — one
    /// request for the whole selection instead of one per song.
    static func removeSongs(_ songs: [BaseItemDto], fromPlaylistId playlistId: String, playlistName: String) {
        guard !songs.isEmpty else { return }
        let entryIds = songs.map { $0.PlaylistItemId ?? $0.Id }
        Task {
            do {
                try await JellyfinAPIClient.shared.removeItemsFromPlaylist(playlistId: playlistId, entryIds: entryIds)
                var removedCount = 0
                for song in songs where await removeFromCachedPlaylist(song, playlistId: playlistId) {
                    removedCount += 1
                }
                if removedCount > 0 {
                    await bumpPlaylistChildCount(playlistId: playlistId, by: -removedCount)
                }
                ToastCenter.shared.show("Removed \(songs.count) song\(songs.count == 1 ? "" : "s") from \(playlistName)")
            } catch {
                ToastCenter.shared.show("Couldn't remove songs from \(playlistName)", isError: true)
            }
        }
    }

    /// Creates a new, empty playlist on the server and adds it to the locally cached playlist list
    /// right away. Returns the new playlist so the caller can, for example, add a song to it or
    /// navigate straight into it.
    @discardableResult
    static func createPlaylist(name: String) async -> BaseItemDto? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let id = try await JellyfinAPIClient.shared.createPlaylist(name: trimmed)
            let playlist = BaseItemDto(
                Id: id, Name: trimmed, ItemType: "Playlist", CollectionType: nil,
                AlbumArtist: nil, Artists: nil, Album: nil, AlbumId: nil,
                ProductionYear: nil, RunTimeTicks: nil, IndexNumber: nil,
                ChildCount: 0, ImageTags: nil, PlaylistItemId: nil,
                PremiereDate: nil, DateCreated: nil, MediaSources: nil, UserData: nil, Genres: nil
            )
            var playlists = await LibraryCache.shared.items(for: "playlists") ?? []
            playlists.insert(playlist, at: 0)
            await LibraryCache.shared.store(playlists, for: "playlists")
            ToastCenter.shared.show("Created \(trimmed)")
            return playlist
        } catch {
            ToastCenter.shared.show("Couldn't create playlist", isError: true)
            return nil
        }
    }

    static func deletePlaylist(_ playlist: BaseItemDto) {
        Task {
            do {
                try await JellyfinAPIClient.shared.deleteItem(itemId: playlist.Id)
                var playlists = await LibraryCache.shared.items(for: "playlists") ?? []
                playlists.removeAll { $0.Id == playlist.Id }
                await LibraryCache.shared.store(playlists, for: "playlists")
                await LibraryCache.shared.remove(for: "playlistSongs:\(playlist.Id)")
                if PinnedPlaylistStore.shared.isPinned(playlist.Id) {
                    PinnedPlaylistStore.shared.unpin()
                }
                ToastCenter.shared.show("Deleted \(playlist.Name)")
            } catch {
                ToastCenter.shared.show("Couldn't delete \(playlist.Name)", isError: true)
            }
        }
    }

    static func renamePlaylist(_ playlist: BaseItemDto, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != playlist.Name else { return }
        Task {
            do {
                try await JellyfinAPIClient.shared.renamePlaylist(playlistId: playlist.Id, name: trimmed)
                var playlists = await LibraryCache.shared.items(for: "playlists") ?? []
                if let index = playlists.firstIndex(where: { $0.Id == playlist.Id }) {
                    playlists[index] = playlists[index].withName(trimmed)
                    await LibraryCache.shared.store(playlists, for: "playlists")
                }
                if PinnedPlaylistStore.shared.isPinned(playlist.Id) {
                    PinnedPlaylistStore.shared.renamePinned(to: trimmed)
                }
                ToastCenter.shared.show("Renamed to \(trimmed)")
            } catch {
                ToastCenter.shared.show("Couldn't rename playlist", isError: true)
            }
        }
    }

    /// Applies a drag reorder the caller already performed locally (see `PlaylistDetailView`, which
    /// splices with `Array.move(fromOffsets:toOffset:)` the same way the queue's reorder does) —
    /// tells the server where the moved song landed, then persists the same new order locally.
    static func moveSong(_ song: BaseItemDto, toIndex: Int, in playlistId: String, newOrder: [BaseItemDto]) {
        let entryId = song.PlaylistItemId ?? song.Id
        Task {
            do {
                try await JellyfinAPIClient.shared.movePlaylistItem(playlistId: playlistId, entryId: entryId, toIndex: toIndex)
                await LibraryCache.shared.store(newOrder, for: "playlistSongs:\(playlistId)")
            } catch {
                ToastCenter.shared.show("Couldn't reorder playlist", isError: true)
            }
        }
    }

    /// Not fire-and-forget like the rest of this file — returns only once the new image is actually
    /// in `ImageCache`, so the caller can refresh whatever's showing it (e.g. by changing its `.id`)
    /// immediately after, instead of racing the background upload.
    @discardableResult
    static func updatePlaylistImage(_ playlist: BaseItemDto, imageData: Data, mimeType: String) async -> Bool {
        do {
            try await JellyfinAPIClient.shared.uploadItemImage(itemId: playlist.Id, imageData: imageData, mimeType: mimeType)
            await ImageCache.shared.store(imageData, itemId: playlist.Id, imageType: "Primary")
            ToastCenter.shared.show("Updated playlist image")
            return true
        } catch {
            ToastCenter.shared.show("Couldn't update playlist image", isError: true)
            return false
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
