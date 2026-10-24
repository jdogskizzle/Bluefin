//
//  PlaylistRefreshService.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 9/4/26.
//

import Foundation

/// Keeps playlists in step with the server on a much shorter cadence than `LibrarySyncManager`'s
/// full library sync — refreshing just the playlist list, or just one playlist's songs, every time
/// the relevant screen appears. Unlike the rest of the library (artists/albums/songs, which only
/// really change when new media is added), a playlist commonly changes from another client — the
/// Jellyfin web UI, another device — between one full sync and the next, so waiting on that full
/// sync to notice would make the app feel stale for exactly the content a user is actively looking
/// at right now.
///
/// Both methods write straight into the same `LibraryCache` keys the full sync uses, so any
/// `LibraryListViewModel` (or `HomeView`'s pinned-playlist section) already on screen picks up the
/// result immediately via `LibraryCacheChangeCenter`, the same way a local mutation does.
enum PlaylistRefreshService {
    /// Refreshes the playlist list itself — picks up playlists created, deleted, or renamed from
    /// another client. Failures are silent: this is a background refresh behind data the cache
    /// already has displayed, not something the user is explicitly waiting on.
    static func refreshPlaylists() async {
        guard let playlists = try? await JellyfinAPIClient.shared.fetchItems(includeItemTypes: "Playlist", mediaTypes: "Audio") else {
            return
        }
        await LibraryCache.shared.store(playlists, for: "playlists")
    }

    /// Refreshes one playlist's song list — picks up songs added, removed, or reordered from
    /// another client.
    static func refreshSongs(forPlaylistId playlistId: String) async {
        guard let items = try? await JellyfinAPIClient.shared.fetchPlaylistItems(
            playlistId: playlistId,
            fields: "DateCreated,MediaSources,UserData"
        ) else {
            return
        }
        await LibraryCache.shared.store(items, for: "playlistSongs:\(playlistId)")
    }
}
