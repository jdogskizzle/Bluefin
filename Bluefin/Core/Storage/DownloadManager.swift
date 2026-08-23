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

enum DownloadedGroupKind: String {
    case artist
    case album
    case playlist
}

/// Identifies the artist/album/playlist a batch download belongs to, so it can be recorded as a
/// single group (see `DownloadedGroup`) instead of just a pile of individually-downloaded songs.
struct DownloadGroupInfo {
    let id: String
    let kind: DownloadedGroupKind
    let name: String
}

/// A downloaded artist/album/playlist, as shown in the Library "Downloads" section.
struct DownloadedGroupSummary: Identifiable {
    let id: String
    let kind: DownloadedGroupKind
    let name: String
    let songIds: Set<String>
}

/// UI-facing coordinator for explicit downloads — orchestrates `DownloadStore.download(item:)` per
/// song and publishes per-item state so every song row, context menu, and container "..." menu
/// across the app can reflect it reactively without each polling the (actor-isolated) store itself.
@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var downloadedItemIds: Set<String> = []
    @Published private(set) var downloadingItemIds: Set<String> = []
    @Published private(set) var downloadedGroups: [DownloadedGroupSummary] = []

    private var downloadTasks: [String: Task<Void, Never>] = [:]
    /// Starting every song in a large batch (e.g. a whole artist) at once was overwhelming the
    /// connection and making individual requests more likely to time out — which silently dropped
    /// songs from the batch with no indication anything had gone wrong. Downloads within a batch
    /// now run in chunks of this size instead.
    private static let maxConcurrentDownloads = 4

    private init() {
        Task {
            await refreshDownloadedIds()
            await refreshDownloadedGroups()
        }
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
        let task = startDownloadTask(for: song)
        Task {
            await task.value
            if !downloadedItemIds.contains(song.Id) {
                ToastCenter.shared.show("Couldn't download \(song.Name)", isError: true)
            }
        }
    }

    /// Downloading a whole album/artist/playlist also records it as a group once every song in it
    /// has actually finished downloading, so the Library "Downloads" section shows just that one
    /// artist/album/playlist rather than every song inside it individually.
    func download(_ songs: [BaseItemDto], group: DownloadGroupInfo? = nil) {
        Task {
            await downloadBounded(songs)
            guard let group else { return }

            let succeededIds = songs.map(\.Id).filter { downloadedItemIds.contains($0) }
            guard !succeededIds.isEmpty else {
                ToastCenter.shared.show("Couldn't download \(group.name)", isError: true)
                return
            }
            await DownloadStore.shared.recordGroup(id: group.id, kind: group.kind.rawValue, name: group.name, songIds: succeededIds)
            await refreshDownloadedGroups()
            if succeededIds.count < songs.count {
                ToastCenter.shared.show("Downloaded \(succeededIds.count) of \(songs.count) songs from \(group.name)", isError: true)
            } else {
                ToastCenter.shared.show("Downloaded \(group.name)")
            }
        }
    }

    /// Runs a batch's downloads in bounded-size chunks rather than all at once (see
    /// `maxConcurrentDownloads`), awaiting each chunk before starting the next.
    private func downloadBounded(_ songs: [BaseItemDto]) async {
        var startIndex = 0
        while startIndex < songs.count {
            let endIndex = min(startIndex + Self.maxConcurrentDownloads, songs.count)
            let tasks = songs[startIndex..<endIndex].map { startDownloadTask(for: $0) }
            for task in tasks { await task.value }
            startIndex = endIndex
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
            await refreshDownloadedGroups()
        }
    }

    /// Removing a whole album/artist/playlist's download also drops its group record.
    func removeDownload(_ songs: [BaseItemDto], group: DownloadGroupInfo? = nil) {
        for song in songs {
            downloadedItemIds.remove(song.Id)
        }
        Task {
            for song in songs {
                await DownloadStore.shared.remove(itemId: song.Id)
            }
            if let group {
                await DownloadStore.shared.removeGroup(id: group.id)
            }
            await refreshDownloadedGroups()
        }
    }

    func refreshDownloadedIds() async {
        downloadedItemIds = await DownloadStore.shared.downloadedTrackIds()
    }

    func refreshDownloadedGroups() async {
        let groups = await DownloadStore.shared.downloadedGroups()
        downloadedGroups = groups.compactMap { info in
            guard let kind = DownloadedGroupKind(rawValue: info.kind) else { return nil }
            return DownloadedGroupSummary(id: info.id, kind: kind, name: info.name, songIds: Set(info.songIds))
        }
    }

    @discardableResult
    private func startDownloadTask(for song: BaseItemDto) -> Task<Void, Never> {
        if let existing = downloadTasks[song.Id] { return existing }
        guard !downloadedItemIds.contains(song.Id) else { return Task {} }

        downloadingItemIds.insert(song.Id)
        let task = Task { [weak self] in
            let succeeded = await DownloadStore.shared.download(item: song)
            guard let self else { return }
            self.downloadTasks[song.Id] = nil
            self.downloadingItemIds.remove(song.Id)
            if succeeded {
                self.downloadedItemIds.insert(song.Id)
            }
        }
        downloadTasks[song.Id] = task
        return task
    }
}
