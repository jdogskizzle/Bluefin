//
//  PlaylistSortPreference.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/22/26.
//

import Combine
import Foundation

enum PlaylistSortOrder: String, Codable {
    case playlistOrder
    case artist
    case alphabetical
    case releaseDate
}

/// A per-playlist, persisted sort order — each playlist remembers its own choice independently,
/// keyed by playlist id, rather than one setting shared across every playlist.
@MainActor
final class PlaylistSortPreference: ObservableObject {
    static let shared = PlaylistSortPreference()

    @Published private var sortOrdersByPlaylistId: [String: PlaylistSortOrder] = [:] {
        didSet {
            guard let data = try? JSONEncoder().encode(sortOrdersByPlaylistId) else { return }
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private static let defaultsKey = "com.bluefin.playlistSortOrders"

    private init() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let stored = try? JSONDecoder().decode([String: PlaylistSortOrder].self, from: data) else {
            return
        }
        sortOrdersByPlaylistId = stored
    }

    func sortOrder(for playlistId: String) -> PlaylistSortOrder {
        sortOrdersByPlaylistId[playlistId] ?? .playlistOrder
    }

    func setSortOrder(_ sortOrder: PlaylistSortOrder, for playlistId: String) {
        sortOrdersByPlaylistId[playlistId] = sortOrder
    }
}
