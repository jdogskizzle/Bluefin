//
//  LibraryListViewModel.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import Foundation

enum LibraryItemKind {
    case song, playlist
}

/// Reads a list screen's items purely from `LibraryCache` — nothing here ever talks to Jellyfin.
/// The cache is populated exclusively by an explicit `LibrarySyncManager.sync()` run from Settings,
/// so a screen shows whatever the last sync produced (or nothing, prompting the user to sync) and
/// never triggers a network call just by being opened.
@MainActor
final class LibraryListViewModel: ObservableObject {
    @Published var items: [BaseItemDto] = []
    @Published private(set) var hasSynced = false

    private let cacheKey: String

    init(cacheKey: String) {
        self.cacheKey = cacheKey
    }

    func load() async {
        if let cached = await LibraryCache.shared.items(for: cacheKey) {
            items = cached
            hasSynced = true
        } else {
            items = []
            hasSynced = false
        }
    }
}
