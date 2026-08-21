//
//  CacheManager.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Foundation
import SwiftData

/// Downloads and evicts locally-cached audio files, backed by `CachedTrack` records.
///
/// This caches whole files in the background rather than intercepting AVPlayer's own byte
/// stream (which would need a custom `AVAssetResourceLoaderDelegate`). The tradeoff: the first
/// play of an uncached track streams it for immediate playback *and* downloads it again in the
/// background for the cache, so it costs roughly 2x bandwidth on first listen. Simpler and more
/// robust than sharing bytes between the two, at that cost.
@ModelActor
actor CacheManager {
    static let shared = CacheManager(modelContainer: Persistence.shared)

    static let cacheLimitDefaultsKey = "com.bluefin.cacheLimitBytes"
    static let defaultCacheLimitBytes: Int64 = 2 * 1_000_000_000

    static var cacheLimitBytes: Int64 {
        get {
            let stored = UserDefaults.standard.object(forKey: cacheLimitDefaultsKey) as? Int64
            return stored ?? defaultCacheLimitBytes
        }
        set {
            UserDefaults.standard.set(newValue, forKey: cacheLimitDefaultsKey)
        }
    }

    static let preCacheLookaheadDefaultsKey = "com.bluefin.preCacheLookahead"
    static let defaultPreCacheLookahead = 10

    /// How many upcoming queue tracks get proactively downloaded ahead of playback.
    static var preCacheLookahead: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: preCacheLookaheadDefaultsKey) as? Int
            return stored ?? defaultPreCacheLookahead
        }
        set {
            UserDefaults.standard.set(newValue, forKey: preCacheLookaheadDefaultsKey)
        }
    }

    private var activeDownloads: Set<String> = []

    private var cacheDirectoryURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("AudioCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Returns the local file for a track if it's fully cached, touching its last-accessed
    /// time so it survives LRU eviction longer.
    func localFileURL(forItemId itemId: String) -> URL? {
        guard let track = fetchTrack(id: itemId),
            track.isDownloaded,
            let path = track.localFilePath,
            FileManager.default.fileExists(atPath: path)
        else {
            return nil
        }
        track.lastAccessedDate = .now
        try? modelContext.save()
        return URL(fileURLWithPath: path)
    }

    /// Cached lyrics if present, otherwise fetches from the server and persists the result
    /// (including an empty result, so a track confirmed to have none isn't re-fetched every time
    /// lyrics are opened). A failed fetch returns an empty result without caching it, so it's
    /// retried on the next attempt.
    func lyrics(for item: BaseItemDto) async -> [LyricLine] {
        if let data = fetchTrack(id: item.Id)?.lyricsData,
           let cached = try? JSONDecoder().decode([LyricLine].self, from: data) {
            return cached
        }

        guard let fetched = try? await JellyfinAPIClient.shared.fetchLyrics(itemId: item.Id) else {
            return []
        }

        if let data = try? JSONEncoder().encode(fetched) {
            if let track = fetchTrack(id: item.Id) {
                track.lyricsData = data
            } else {
                let track = CachedTrack(item: item)
                track.lyricsData = data
                modelContext.insert(track)
            }
            try? modelContext.save()
        }
        return fetched
    }

    /// Downloads a track to the cache if it isn't already cached or in flight. Safe to call
    /// repeatedly (e.g. once for the current track, once for pre-caching the next).
    func cacheTrack(
        id: String, title: String, artistName: String, albumName: String, albumId: String?,
        durationTicks: Int64, remoteURL: URL
    ) async {
        guard localFileURL(forItemId: id) == nil, !activeDownloads.contains(id) else { return }
        activeDownloads.insert(id)
        defer { activeDownloads.remove(id) }

        do {
            let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
            else {
                try? FileManager.default.removeItem(at: tempURL)
                return
            }

            // Unlike a network URL, a local file has no Content-Type for AVPlayer to sniff — it
            // relies on the path extension to pick a demuxer, so we derive one from the response.
            let ext = Self.fileExtension(
                forMIMEType: http.value(forHTTPHeaderField: "Content-Type"))
            let destinationURL = cacheDirectoryURL.appendingPathComponent("\(id).\(ext)")
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)

            let attributes = try? FileManager.default.attributesOfItem(atPath: destinationURL.path)
            let fileSize = (attributes?[.size] as? Int64) ?? 0

            if let track = fetchTrack(id: id) {
                track.localFilePath = destinationURL.path
                track.isDownloaded = true
                track.fileSizeBytes = fileSize
                track.lastAccessedDate = .now
            } else {
                let track = CachedTrack(
                    id: id,
                    title: title,
                    artistName: artistName,
                    albumName: albumName,
                    albumId: albumId,
                    durationTicks: durationTicks,
                    localFilePath: destinationURL.path,
                    isDownloaded: true,
                    fileSizeBytes: fileSize
                )
                modelContext.insert(track)
            }
            try? modelContext.save()
            evictIfOverLimit()
        } catch {
            // Streaming already served playback; a failed background cache attempt just means
            // this track stays uncached until the next play.
        }
    }

    func totalCacheSizeBytes() -> Int64 {
        let descriptor = FetchDescriptor<CachedTrack>(predicate: #Predicate { $0.isDownloaded })
        let tracks = (try? modelContext.fetch(descriptor)) ?? []
        return tracks.reduce(Int64(0)) { $0 + ($1.fileSizeBytes ?? 0) }
    }

    func clearCache() {
        let descriptor = FetchDescriptor<CachedTrack>(predicate: #Predicate { $0.isDownloaded })
        let tracks = (try? modelContext.fetch(descriptor)) ?? []
        for track in tracks {
            evict(track)
        }
        try? modelContext.save()
    }

    private func evictIfOverLimit() {
        let limit = Self.cacheLimitBytes
        let descriptor = FetchDescriptor<CachedTrack>(
            predicate: #Predicate { $0.isDownloaded },
            sortBy: [SortDescriptor(\.lastAccessedDate, order: .forward)]
        )
        let tracks = (try? modelContext.fetch(descriptor)) ?? []
        var total = tracks.reduce(Int64(0)) { $0 + ($1.fileSizeBytes ?? 0) }

        for track in tracks {
            guard total > limit else { break }
            total -= track.fileSizeBytes ?? 0
            evict(track)
        }
        try? modelContext.save()
    }

    private func evict(_ track: CachedTrack) {
        if let path = track.localFilePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        track.isDownloaded = false
        track.localFilePath = nil
        track.fileSizeBytes = nil
    }

    private func fetchTrack(id: String) -> CachedTrack? {
        let descriptor = FetchDescriptor<CachedTrack>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private static func fileExtension(forMIMEType mimeType: String?) -> String {
        switch mimeType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces)
            .lowercased()
        {
        case "audio/flac", "audio/x-flac": return "flac"
        case "audio/mp4", "audio/x-m4a", "audio/m4a", "audio/alac": return "m4a"
        case "audio/aac": return "aac"
        case "audio/ogg", "audio/opus": return "ogg"
        case "audio/wav", "audio/x-wav", "audio/wave": return "wav"
        default: return "mp3"
        }
    }
}
