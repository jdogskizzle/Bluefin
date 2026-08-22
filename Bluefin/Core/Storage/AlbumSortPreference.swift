//
//  AlbumSortPreference.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/21/26.
//

import Combine
import Foundation

enum AlbumSortOrder: String {
    case releaseDateAscending
    case releaseDateDescending
}

/// A single, persisted, app-wide sort order for an artist's albums — set from any artist page,
/// applies to every artist page, not just the one it was changed from.
@MainActor
final class AlbumSortPreference: ObservableObject {
    static let shared = AlbumSortPreference()

    @Published var sortOrder: AlbumSortOrder {
        didSet {
            UserDefaults.standard.set(sortOrder.rawValue, forKey: Self.defaultsKey)
        }
    }

    private static let defaultsKey = "com.bluefin.artistAlbumSortOrder"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey), let stored = AlbumSortOrder(rawValue: raw) {
            sortOrder = stored
        } else {
            sortOrder = .releaseDateAscending
        }
    }
}
