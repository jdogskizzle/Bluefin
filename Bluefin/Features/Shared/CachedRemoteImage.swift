//
//  CachedRemoteImage.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/23/26.
//

import SwiftUI

/// In-memory, session-only cache for images loaded from a plain remote URL — for content like
/// Lidarr album covers that isn't a Jellyfin item and so has no id `ImageCache` could key off of.
/// Not persisted to disk (unlike `ImageCache`): these covers can change and aren't worth the extra
/// invalidation complexity for what's fundamentally a small, short-lived data set.
actor RemoteImageCache {
    static let shared = RemoteImageCache()

    private var imagesByURL: [URL: Data] = [:]

    private init() {}

    func data(for url: URL) -> Data? {
        imagesByURL[url]
    }

    func store(_ data: Data, for url: URL) {
        imagesByURL[url] = data
    }
}

/// Drop-in replacement for `AsyncImage(url:content:placeholder:)` that checks `RemoteImageCache`
/// first — without this, navigating between the Home strip, an artist's page, and the full "Upcoming
/// Releases" grid each re-downloaded the same Lidarr cover image from scratch, since a plain
/// `AsyncImage` has no cache shared across separate view instances.
struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            uiImage = nil
            await load()
        }
    }

    private func load() async {
        guard let url else { return }

        if let cached = await RemoteImageCache.shared.data(for: url), let image = UIImage(data: cached) {
            uiImage = image
            return
        }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let image = UIImage(data: data) else {
            return
        }

        uiImage = image
        await RemoteImageCache.shared.store(data, for: url)
    }
}
