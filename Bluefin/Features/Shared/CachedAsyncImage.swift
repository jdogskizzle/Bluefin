//
//  CachedAsyncImage.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import SwiftUI

/// Drop-in replacement for `AsyncImage(url:content:placeholder:)` that checks `ImageCache` before
/// hitting the network. A user-triggered library sync is what's meant to proactively fill this
/// cache for browsing (see `LibrarySyncManager`); this view's own network fallback exists only so
/// something not yet synced — most notably whatever's actively playing — still shows artwork
/// immediately rather than a blank placeholder, and it persists what it fetches so that fallback
/// doesn't repeat next time.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let itemId: String
    var imageType: String = "Primary"
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
        .task(id: "\(itemId)_\(imageType)") {
            uiImage = nil
            await load()
        }
    }

    private func load() async {
        if let cached = await ImageCache.shared.data(itemId: itemId, imageType: imageType),
           let image = UIImage(data: cached) {
            uiImage = image
            return
        }

        let width = ImageCache.canonicalWidth(forImageType: imageType)
        guard let url = JellyfinAPIClient.shared.imageURL(itemId: itemId, imageType: imageType, maxWidth: width) else { return }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let image = UIImage(data: data) else { return }

        uiImage = image
        await ImageCache.shared.store(data, itemId: itemId, imageType: imageType)
    }
}
