//
//  DownloadStore.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/22/26.
//

import Foundation
import SwiftData

/// Explicit, user-requested downloads — a real, permanent copy fetched fresh from the server, kept
/// entirely separate from `CacheManager`'s opportunistic pre-cache: its own `DownloadedTrack`
/// records, its own directory under Application Support (excluded from iCloud backup, since large
/// media shouldn't be backed up), and its own eviction-free lifetime. Even a song that's already
/// opportunistically cached gets downloaded again here rather than promoted/copied in place — the
/// two stores never share a file on disk, so clearing one can never affect the other.
@ModelActor
actor DownloadStore {
    static let shared = DownloadStore(modelContainer: Persistence.shared)

    private var activeDownloads: Set<String> = []

    private var downloadsDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Downloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var excludedDirectory = directory
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? excludedDirectory.setResourceValues(resourceValues)
        }
        return directory
    }

    func isDownloaded(_ itemId: String) -> Bool {
        fetchTrack(id: itemId) != nil
    }

    func localFileURL(forItemId itemId: String) -> URL? {
        guard let track = fetchTrack(id: itemId), FileManager.default.fileExists(atPath: track.localFilePath) else {
            return nil
        }
        return URL(fileURLWithPath: track.localFilePath)
    }

    func downloadedTrackIds() -> Set<String> {
        let descriptor = FetchDescriptor<DownloadedTrack>()
        let tracks = (try? modelContext.fetch(descriptor)) ?? []
        return Set(tracks.map(\.id))
    }

    /// Downloads `item` fresh from the server if it isn't already downloaded or in flight, retrying
    /// a couple of times on failure — across a large batch (e.g. a whole artist), a handful of
    /// individual requests timing out or hiccuping is common enough that a silent single attempt
    /// was leaving songs quietly missing. Cooperatively cancellable — `DownloadManager` cancels the
    /// enclosing `Task`, which is checked between attempts so a cancelled download doesn't retry.
    @discardableResult
    func download(item: BaseItemDto) async -> Bool {
        if fetchTrack(id: item.Id) != nil { return true }
        guard !activeDownloads.contains(item.Id) else { return false }
        let bitrate = await StreamingQualitySettings.shared.downloadQuality.bitRateKbps
        guard let remoteURL = await JellyfinAPIClient.shared.streamURL(itemId: item.Id, maxBitrateKbps: bitrate) else { return false }

        activeDownloads.insert(item.Id)
        defer { activeDownloads.remove(item.Id) }

        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            guard !Task.isCancelled else { return false }
            if await attemptDownload(item: item, from: remoteURL) {
                return true
            }
            guard attempt < maxAttempts else { return false }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    private func attemptDownload(item: BaseItemDto, from remoteURL: URL) async -> Bool {
        do {
            let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: tempURL)
                return false
            }

            // Unlike a network URL, a local file has no Content-Type for AVPlayer to sniff — it
            // relies on the path extension to pick a demuxer, so we derive one from the response.
            let ext = Self.fileExtension(forMIMEType: http.value(forHTTPHeaderField: "Content-Type"))
            let destinationURL = downloadsDirectoryURL.appendingPathComponent("\(item.Id).\(ext)")
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)

            let attributes = try? FileManager.default.attributesOfItem(atPath: destinationURL.path)
            let fileSize = (attributes?[.size] as? Int64) ?? 0

            let track = DownloadedTrack(item: item, localFilePath: destinationURL.path, fileSizeBytes: fileSize)
            modelContext.insert(track)
            try? modelContext.save()
            return true
        } catch {
            // A failed attempt just means this one didn't land — the caller retries or gives up.
            return false
        }
    }

    func remove(itemId: String) {
        guard let track = fetchTrack(id: itemId) else { return }
        try? FileManager.default.removeItem(atPath: track.localFilePath)
        modelContext.delete(track)
        deleteGroups(containingSongId: itemId)
        try? modelContext.save()
    }

    func clearAll() {
        let descriptor = FetchDescriptor<DownloadedTrack>()
        let tracks = (try? modelContext.fetch(descriptor)) ?? []
        for track in tracks {
            try? FileManager.default.removeItem(atPath: track.localFilePath)
            modelContext.delete(track)
        }
        let groupDescriptor = FetchDescriptor<DownloadedGroup>()
        let groups = (try? modelContext.fetch(groupDescriptor)) ?? []
        for group in groups {
            modelContext.delete(group)
        }
        try? modelContext.save()
    }

    struct GroupInfo: Sendable {
        let id: String
        let kind: String
        let name: String
        let songIds: [String]
    }

    /// Records (or updates) that a whole artist/album/playlist was downloaded as a unit.
    func recordGroup(id: String, kind: String, name: String, songIds: [String]) {
        let descriptor = FetchDescriptor<DownloadedGroup>(predicate: #Predicate { $0.id == id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.kind = kind
            existing.name = name
            existing.songIds = songIds
        } else {
            modelContext.insert(DownloadedGroup(id: id, kind: kind, name: name, songIds: songIds))
        }
        try? modelContext.save()
    }

    func removeGroup(id: String) {
        let descriptor = FetchDescriptor<DownloadedGroup>(predicate: #Predicate { $0.id == id })
        guard let entry = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(entry)
        try? modelContext.save()
    }

    func downloadedGroups() -> [GroupInfo] {
        let descriptor = FetchDescriptor<DownloadedGroup>()
        let groups = (try? modelContext.fetch(descriptor)) ?? []
        return groups.map { GroupInfo(id: $0.id, kind: $0.kind, name: $0.name, songIds: $0.songIds) }
    }

    /// A group is only meaningful while every one of its songs is still downloaded — deletes any
    /// group containing `songId` rather than leaving a partial one; its other songs simply fall
    /// back to showing individually.
    private func deleteGroups(containingSongId songId: String) {
        let descriptor = FetchDescriptor<DownloadedGroup>()
        let groups = (try? modelContext.fetch(descriptor)) ?? []
        for group in groups where group.songIds.contains(songId) {
            modelContext.delete(group)
        }
    }

    func count() -> Int {
        let descriptor = FetchDescriptor<DownloadedTrack>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    func totalSizeBytes() -> Int64 {
        let descriptor = FetchDescriptor<DownloadedTrack>()
        let tracks = (try? modelContext.fetch(descriptor)) ?? []
        return tracks.reduce(Int64(0)) { $0 + $1.fileSizeBytes }
    }

    private func fetchTrack(id: String) -> DownloadedTrack? {
        let descriptor = FetchDescriptor<DownloadedTrack>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private static func fileExtension(forMIMEType mimeType: String?) -> String {
        switch mimeType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "audio/flac", "audio/x-flac": return "flac"
        case "audio/mp4", "audio/x-m4a", "audio/m4a", "audio/alac": return "m4a"
        case "audio/aac": return "aac"
        case "audio/ogg", "audio/opus": return "ogg"
        case "audio/wav", "audio/x-wav", "audio/wave": return "wav"
        default: return "mp3"
        }
    }
}
