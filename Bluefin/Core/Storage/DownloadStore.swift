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

    /// Downloads `item` fresh from the server if it isn't already downloaded or in flight.
    /// Cooperatively cancellable — `DownloadManager` cancels the enclosing `Task`, which surfaces
    /// here as a thrown `CancellationError`/`URLError.cancelled` from `URLSession`.
    func download(item: BaseItemDto) async {
        guard fetchTrack(id: item.Id) == nil, !activeDownloads.contains(item.Id),
              let remoteURL = await JellyfinAPIClient.shared.streamURL(itemId: item.Id) else { return }

        activeDownloads.insert(item.Id)
        defer { activeDownloads.remove(item.Id) }

        do {
            let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: tempURL)
                return
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
        } catch {
            // A failed or cancelled download just means this track stays undownloaded.
        }
    }

    func remove(itemId: String) {
        guard let track = fetchTrack(id: itemId) else { return }
        try? FileManager.default.removeItem(atPath: track.localFilePath)
        modelContext.delete(track)
        try? modelContext.save()
    }

    func clearAll() {
        let descriptor = FetchDescriptor<DownloadedTrack>()
        let tracks = (try? modelContext.fetch(descriptor)) ?? []
        for track in tracks {
            try? FileManager.default.removeItem(atPath: track.localFilePath)
            modelContext.delete(track)
        }
        try? modelContext.save()
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
