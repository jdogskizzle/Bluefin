//
//  LibrarySyncManager.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Combine
import Foundation

/// Explicitly, user-triggered full sync of the selected library into `LibraryCache` (metadata),
/// `ImageCache` (artwork), and `CacheManager` (lyrics). Nothing populates these caches on its own —
/// browsing/lyrics screens only ever read what a sync (or, for lyrics specifically, having viewed
/// that one track's lyrics before) has already put there — so this is the *only* place that
/// proactively pulls library content from Jellyfin.
///
/// Album-song lists are derived locally from the one whole-library song fetch (grouped by album id,
/// sorted by track number) rather than issued as one network call per album, since Jellyfin already
/// gives us everything needed for that in a single request. Playlist-song lists and per-artist album
/// lists can't be derived the same way — Jellyfin doesn't expose playlist membership or artist-id
/// linkage on a plain song/album record — so those go out as one request per playlist/artist.
@MainActor
final class LibrarySyncManager: ObservableObject {
    static let shared = LibrarySyncManager()

    enum Step: String, CaseIterable {
        case artists = "Artists"
        case albums = "Albums"
        case songs = "Songs"
        case playlists = "Playlists"
        case playlistSongs = "Playlist Songs"
        case artistAlbums = "Artist Albums"
        case artwork = "Artwork"
        case lyrics = "Lyrics"
    }

    enum Phase: Equatable {
        case idle
        case syncing(step: Step, completed: Int, total: Int)
        case finished
        case failed(String)
    }

    private struct ArtworkTarget: Sendable {
        let itemId: String
        let imageType: String
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastSyncedAt: Date?

    private static let lastSyncedDefaultsKey = "com.bluefin.lastLibrarySync"
    /// Referenced from inside a concurrent `forEachConcurrently` closure, which isn't on the
    /// main actor — needs to be reachable without hopping actors for a plain constant.
    private nonisolated static let variousArtistsThreshold = 10
    private static let maxConcurrentRequests = 6

    private init() {
        lastSyncedAt = UserDefaults.standard.object(forKey: Self.lastSyncedDefaultsKey) as? Date
    }

    var isSyncing: Bool {
        if case .syncing = phase { return true }
        return false
    }

    /// Overall progress across all steps, for a single combined progress bar.
    var overallProgress: Double {
        guard case .syncing(let step, let completed, let total) = phase,
              let index = Step.allCases.firstIndex(of: step) else {
            return 0
        }
        let withinStep = total > 0 ? Double(completed) / Double(total) : 0
        return (Double(index) + withinStep) / Double(Step.allCases.count)
    }

    func sync() async {
        guard !isSyncing else { return }

        guard let libraryId = JellyfinAPIClient.shared.selectedLibraryId else {
            phase = .failed("Select a music library in Settings first.")
            return
        }

        do {
            phase = .syncing(step: .artists, completed: 0, total: 1)
            let artists = try await JellyfinAPIClient.shared.fetchItems(parentId: libraryId, includeItemTypes: "MusicArtist")
            await LibraryCache.shared.store(artists, for: "artists:\(libraryId)")

            phase = .syncing(step: .albums, completed: 0, total: 1)
            let albums = try await JellyfinAPIClient.shared.fetchItems(
                parentId: libraryId,
                includeItemTypes: "MusicAlbum",
                fields: "PremiereDate"
            )
            await LibraryCache.shared.store(albums, for: "albums:\(libraryId)")

            phase = .syncing(step: .songs, completed: 0, total: 1)
            let songs = try await JellyfinAPIClient.shared.fetchItems(
                parentId: libraryId,
                includeItemTypes: "Audio",
                fields: "DateCreated,MediaSources,UserData"
            )
            await LibraryCache.shared.store(songs, for: "songs:\(libraryId)")

            let songsByAlbum = Dictionary(grouping: songs) { $0.AlbumId ?? "" }
            for (albumId, albumSongs) in songsByAlbum where !albumId.isEmpty {
                let sorted = albumSongs.sorted { ($0.IndexNumber ?? 0) < ($1.IndexNumber ?? 0) }
                await LibraryCache.shared.store(sorted, for: "albumSongs:\(albumId)")
            }

            phase = .syncing(step: .playlists, completed: 0, total: 1)
            let playlists = try await JellyfinAPIClient.shared.fetchItems(includeItemTypes: "Playlist", mediaTypes: "Audio")
            await LibraryCache.shared.store(playlists, for: "playlists")

            await forEachConcurrently(playlists, step: .playlistSongs) { playlist in
                guard let items = try? await JellyfinAPIClient.shared.fetchPlaylistItems(
                    playlistId: playlist.Id,
                    fields: "DateCreated,MediaSources,UserData"
                ) else { return }
                await LibraryCache.shared.store(items, for: "playlistSongs:\(playlist.Id)")
            }

            await forEachConcurrently(artists, step: .artistAlbums) { artist in
                guard let artistAlbums = try? await JellyfinAPIClient.shared.fetchItems(
                    parentId: libraryId,
                    includeItemTypes: "MusicAlbum",
                    artistIds: artist.Id,
                    sortBy: "PremiereDate",
                    fields: "PremiereDate"
                ) else { return }
                let filtered = artistAlbums.filter { ($0.Artists?.count ?? 0) <= Self.variousArtistsThreshold }
                await LibraryCache.shared.store(filtered, for: "artistAlbums:\(artist.Id)")
            }

            var artworkTargets = (artists + albums + playlists).map { ArtworkTarget(itemId: $0.Id, imageType: "Primary") }
            artworkTargets += artists.map { ArtworkTarget(itemId: $0.Id, imageType: "Backdrop") }
            await forEachConcurrently(artworkTargets, step: .artwork) { target in
                await ImageCache.shared.fetchAndStore(itemId: target.itemId, imageType: target.imageType)
            }

            // `CacheManager.lyrics(for:)` already checks its own cache before fetching, so a song
            // synced (or simply viewed) before is skipped here rather than re-fetched.
            await forEachConcurrently(songs, step: .lyrics) { song in
                _ = await CacheManager.shared.lyrics(for: song)
            }

            lastSyncedAt = .now
            UserDefaults.standard.set(lastSyncedAt, forKey: Self.lastSyncedDefaultsKey)
            await FavoritesStore.shared.refreshFromSync()
            phase = .finished
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Runs `operation` over `items` with bounded concurrency, updating `phase` as each completes.
    /// `operation` is expected to swallow its own per-item failures (via `try?`) — one flaky
    /// request shouldn't abort an otherwise multi-minute sync, it should just leave that one item
    /// unsynced until the next sync attempt.
    private func forEachConcurrently<T: Sendable>(_ items: [T], step: Step, _ operation: @escaping @Sendable (T) async -> Void) async {
        guard !items.isEmpty else {
            phase = .syncing(step: step, completed: 0, total: 0)
            return
        }
        phase = .syncing(step: step, completed: 0, total: items.count)

        var completed = 0
        await withTaskGroup(of: Void.self) { group in
            var iterator = items.makeIterator()
            for _ in 0..<min(Self.maxConcurrentRequests, items.count) {
                if let item = iterator.next() {
                    group.addTask { await operation(item) }
                }
            }
            while await group.next() != nil {
                completed += 1
                phase = .syncing(step: step, completed: completed, total: items.count)
                if let item = iterator.next() {
                    group.addTask { await operation(item) }
                }
            }
        }
    }
}
