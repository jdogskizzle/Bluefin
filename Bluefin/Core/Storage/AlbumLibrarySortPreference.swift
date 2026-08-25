//
//  AlbumLibrarySortPreference.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/24/26.
//

import Combine
import Foundation

enum AlbumLibrarySortOrder: String, CaseIterable {
    case title
    case releaseDateAscending
    case releaseDateDescending
    case artistName
}

/// A persisted sort order for the top-level "all albums" library page only — deliberately separate
/// from `AlbumSortPreference` (an artist's own album page), which keeps its own release-date-only
/// sort untouched by this.
@MainActor
final class AlbumLibrarySortPreference: ObservableObject {
    static let shared = AlbumLibrarySortPreference()

    @Published var sortOrder: AlbumLibrarySortOrder {
        didSet {
            UserDefaults.standard.set(sortOrder.rawValue, forKey: Self.defaultsKey)
        }
    }

    private static let defaultsKey = "com.bluefin.albumLibrarySortOrder"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey), let stored = AlbumLibrarySortOrder(rawValue: raw) {
            sortOrder = stored
        } else {
            sortOrder = .title
        }
    }
}
