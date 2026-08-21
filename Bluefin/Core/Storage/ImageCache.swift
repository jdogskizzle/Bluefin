//
//  ImageCache.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Foundation

/// Disk-backed cache for artwork (album/artist/playlist images), keyed by item id + image type.
/// Each image type is fetched and stored at one canonical width for every caller — not the width
/// the current screen happens to want — so a library sync populates exactly the files a screen
/// will look for later, regardless of whether that screen renders it small (a list row) or large
/// (a detail header). SwiftUI downscales the cached image for smaller layouts fine.
/// Kept separate from `CacheManager`/`CachedTrack`: images aren't tied to a single track, and their
/// files are small enough not to need SwiftData bookkeeping — plain file-system LRU is enough.
actor ImageCache {
    static let shared = ImageCache()

    static func canonicalWidth(forImageType imageType: String) -> Int {
        imageType == "Backdrop" ? 1200 : 600
    }

    /// Deliberately not user-configurable like the audio cache limit: images are a couple hundred
    /// KB each, so this is a low-stakes housekeeping cap rather than something worth a Settings row.
    private static let maxCacheBytes: Int64 = 500 * 1_000_000

    private var directoryURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("ImageCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func fileURL(itemId: String, imageType: String) -> URL {
        directoryURL.appendingPathComponent("\(itemId)_\(imageType)")
    }

    /// Cached image bytes if present, touching the file's modification date so it survives LRU
    /// eviction longer.
    func data(itemId: String, imageType: String) -> Data? {
        let url = fileURL(itemId: itemId, imageType: imageType)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    func store(_ data: Data, itemId: String, imageType: String) {
        let url = fileURL(itemId: itemId, imageType: imageType)
        try? data.write(to: url)
        evictIfOverLimit()
    }

    /// Fetches from the server and caches it if not already cached. Used by the explicit library
    /// sync to eagerly populate artwork; safe to call for items that turn out to have no image.
    func fetchAndStore(itemId: String, imageType: String = "Primary") async {
        guard data(itemId: itemId, imageType: imageType) == nil else { return }
        guard let url = await JellyfinAPIClient.shared.imageURL(itemId: itemId, imageType: imageType, maxWidth: Self.canonicalWidth(forImageType: imageType)) else { return }
        guard let (fetched, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
        store(fetched, itemId: itemId, imageType: imageType)
    }

    private func evictIfOverLimit() {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        let entries = urls.compactMap { url -> (url: URL, date: Date, size: Int64)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = values.contentModificationDate,
                  let size = values.fileSize else { return nil }
            return (url, date, Int64(size))
        }.sorted { $0.date < $1.date }

        var total = entries.reduce(Int64(0)) { $0 + $1.size }
        guard total > Self.maxCacheBytes else { return }

        for entry in entries {
            guard total > Self.maxCacheBytes else { break }
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
