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

    private init() {}

    func tracks(forAlbumId albumId: Int) -> [LidarrTrack]? {
        tracksByAlbumId[albumId]
    }

    func refresh() async {
        guard LidarrAPIClient.shared.isConnected,
              let releases = try? await LidarrAPIClient.shared.fetchUpcomingReleases() else {
            upcomingReleases = []
            tracksByAlbumId = [:]
            return
        }
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
