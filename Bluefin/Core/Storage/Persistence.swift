//
//  Persistence.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Foundation
import SwiftData

/// Shared `ModelContainer`, so both the app's SwiftUI scene and background actors like
/// `CacheManager` can open a context against the same store.
enum Persistence {
    static let shared: ModelContainer = {
        let schema = Schema([
            CachedTrack.self,
            ListeningListAlbum.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}
