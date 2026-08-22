//
//  DownloadManager.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/22/26.
//

import Combine
import Foundation

/// The state a song/album/artist/playlist's download button should show.
enum DownloadState {
    case notDownloaded
    case downloading
    case downloaded
}

/// UI-facing coordinator for explicit downloads — orchestrates `DownloadStore.download(item:)` per
/// song and publishes per-item state so every song row, context menu, and container "..." menu
/// across the app can reflect it reactively without each polling the (actor-isolated) store itself.
@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var downloadedItemIds: Set<String> = []
    @Published private(set) var downloadingItemIds: Set<String> = []

    private var downloadTasks: [String: Task<Void, Never>] = [:]

    private init() {
        Task { await refreshDownloadedIds() }
    }

    func state(for itemId: String) -> DownloadState {
        if downloadingItemIds.contains(itemId) { return .downloading }
        if downloadedItemIds.contains(itemId) { return .downloaded }
        return .notDownloaded
    }

    /// The combined state of a whole container (album/artist/playlist): downloading if any of its
    /// songs are, downloaded only once every song is, otherwise not-downloaded.
    func state(for songs: [BaseItemDto]) -> DownloadState {
        guard !songs.isEmpty else { return .notDownloaded }
        if songs.contains(where: { downloadingItemIds.contains($0.Id) }) { return .downloading }
        if songs.allSatisfy({ downloadedItemIds.contains($0.Id) }) { return .downloaded }
        return .notDownloaded
    }

    func download(_ song: BaseItemDto) {
        guard downloadTasks[song.Id] == nil, !downloadedItemIds.contains(song.Id) else { return }
        downloadingItemIds.insert(song.Id)
        downloadTasks[song.Id] = Task {
            await DownloadStore.shared.download(item: song)
            downloadTasks[song.Id] = nil
            downloadingItemIds.remove(song.Id)
            if await DownloadStore.shared.isDownloaded(song.Id) {
                downloadedItemIds.insert(song.Id)
            }
        }
    }

    func download(_ songs: [BaseItemDto]) {
        for song in songs {
            download(song)
        }
    }

    func cancelDownload(_ song: BaseItemDto) {
        downloadTasks[song.Id]?.cancel()
        downloadTasks[song.Id] = nil
        downloadingItemIds.remove(song.Id)
    }

    func cancelDownload(_ songs: [BaseItemDto]) {
        for song in songs {
            cancelDownload(song)
        }
    }

    func removeDownload(_ song: BaseItemDto) {
        downloadedItemIds.remove(song.Id)
        Task {
            await DownloadStore.shared.remove(itemId: song.Id)
        }
    }

    func removeDownload(_ songs: [BaseItemDto]) {
        for song in songs {
            removeDownload(song)
        }
    }

    func refreshDownloadedIds() async {
        downloadedItemIds = await DownloadStore.shared.downloadedTrackIds()
    }
}
