//
//  LidarrReleaseCache.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/21/26.
//

import Combine
import Foundation

/// Upcoming releases and their track listings, fetched together up front (once per app session,
/// triggered from `HomeView`) so opening `LidarrAlbumDetailView` later just reads from here instead
/// of making its own network round trip.
@MainActor
final class LidarrReleaseCache: ObservableObject {
    static let shared = LidarrReleaseCache()

    @Published private(set) var upcomingReleases: [LidarrCalendarItem] = []
    @Published private(set) var tracksByAlbumId: [Int: [LidarrTrack]] = [:]

    /// Set once a fetch has actually completed for the current connection. `HomeView`'s `.task`
    /// re-runs `refresh()` every time it reappears — SwiftUI can tear down and rebuild an inactive
    /// tab's view hierarchy, which restarts `.task` modifiers even though nothing actually changed —
    /// so without this guard, switching tabs and back would silently re-fetch from Lidarr again on
    /// every visit.
    private var hasLoaded = false

    private init() {}

    func tracks(forAlbumId albumId: Int) -> [LidarrTrack]? {
        tracksByAlbumId[albumId]
    }

    func refresh() async {
        guard LidarrAPIClient.shared.isConnected else {
            hasLoaded = false
            upcomingReleases = []
            tracksByAlbumId = [:]
            return
        }
        guard !hasLoaded else { return }

        guard let releases = try? await LidarrAPIClient.shared.fetchUpcomingReleases() else {
            upcomingReleases = []
            tracksByAlbumId = [:]
            return
        }
        hasLoaded = true
        upcomingReleases = releases

        await withTaskGroup(of: (Int, [LidarrTrack]?).self) { group in
            for release in releases {
                group.addTask {
                    let tracks = try? await LidarrAPIClient.shared.fetchTracks(albumId: release.id)
                    return (release.id, tracks)
                }
            }
            for await (albumId, tracks) in group {
                if let tracks {
                    tracksByAlbumId[albumId] = tracks
                }
            }
        }
    }
}
