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
///
/// Also persisted to disk: Lidarr is commonly kept LAN-only (unlike a reverse-proxied Jellyfin), so
/// there's no guarantee a given app launch can actually reach it. Without persistence, every launch
/// away from home would blank out "Upcoming Releases" the moment `refresh()`'s fetch failed, even
/// though nothing about the releases themselves actually changed — persisting means the last known
/// results keep showing until a fetch actually succeeds with fresher ones.
@MainActor
final class LidarrReleaseCache: ObservableObject {
    static let shared = LidarrReleaseCache()

    @Published private(set) var upcomingReleases: [LidarrCalendarItem] = []
    @Published private(set) var tracksByAlbumId: [Int: [LidarrTrack]] = [:]

    /// Set once a fetch has actually completed for the current connection. `HomeView`'s `.task`
    /// re-runs `refresh()` every time it reappears — SwiftUI can tear down and rebuild an inactive
    /// tab's view hierarchy, which restarts `.task` modifiers even though nothing actually changed —
    /// so without this guard, switching tabs and back would silently re-fetch from Lidarr again on
    /// every visit. `refresh(force:)` bypasses it for an explicit pull-to-refresh.
    private var hasLoaded = false

    private static let defaultsKey = "com.bluefin.lidarrReleaseCache"

    private struct PersistedReleases: Codable {
        let releases: [LidarrCalendarItem]
        let tracksByAlbumId: [Int: [LidarrTrack]]
    }

    private init() {
        loadPersisted()
    }

    func tracks(forAlbumId albumId: Int) -> [LidarrTrack]? {
        tracksByAlbumId[albumId]
    }

    func refresh(force: Bool = false) async {
        guard LidarrAPIClient.shared.isConnected else {
            hasLoaded = false
            upcomingReleases = []
            tracksByAlbumId = [:]
            clearPersisted()
            return
        }
        guard force || !hasLoaded else { return }

        // A failed fetch (most commonly: Lidarr unreachable from outside the home network) leaves
        // whatever was last persisted on screen rather than blanking the section — `hasLoaded` stays
        // false so the next reappearance or pull-to-refresh tries again.
        guard let releases = try? await LidarrAPIClient.shared.fetchUpcomingReleases() else {
            return
        }
        hasLoaded = true
        upcomingReleases = releases

        var newTracksByAlbumId: [Int: [LidarrTrack]] = [:]
        await withTaskGroup(of: (Int, [LidarrTrack]?).self) { group in
            for release in releases {
                group.addTask {
                    let tracks = try? await LidarrAPIClient.shared.fetchTracks(albumId: release.id)
                    return (release.id, tracks)
                }
            }
            for await (albumId, tracks) in group {
                if let tracks {
                    newTracksByAlbumId[albumId] = tracks
                }
            }
        }
        tracksByAlbumId = newTracksByAlbumId
        persist()
    }

    private func loadPersisted() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let persisted = try? JSONDecoder().decode(PersistedReleases.self, from: data) else { return }
        upcomingReleases = persisted.releases
        tracksByAlbumId = persisted.tracksByAlbumId
    }

    private func persist() {
        let persisted = PersistedReleases(releases: upcomingReleases, tracksByAlbumId: tracksByAlbumId)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private func clearPersisted() {
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }
}
