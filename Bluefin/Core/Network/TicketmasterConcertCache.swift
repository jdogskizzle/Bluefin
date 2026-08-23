//
//  TicketmasterConcertCache.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/23/26.
//

import Combine
import Foundation

/// A library artist paired with their upcoming Ticketmaster tour dates — what the Home screen's
/// "Upcoming Concerts" section and its detail view are built from.
struct ArtistConcerts: Identifiable, Hashable {
    let artistId: String
    let artistName: String
    let events: [TicketmasterEvent]

    var id: String { artistId }
    var nextDate: Date? { events.first?.date }
}

/// Upcoming concerts for every artist in the synced library, fetched together up front (once per app
/// session, triggered from `HomeView`) the same way `LidarrReleaseCache` fetches releases — so
/// opening the concerts list for one artist later just reads from here instead of making its own
/// network round trip.
@MainActor
final class TicketmasterConcertCache: ObservableObject {
    static let shared = TicketmasterConcertCache()

    @Published private(set) var artistConcerts: [ArtistConcerts] = []

    /// Ticketmaster's free-tier API key enforces roughly 5 requests/second — searching every library
    /// artist at once would burst well past that and mostly come back as rate-limit errors, so this
    /// caps how many run concurrently instead.
    private static let maxConcurrentRequests = 4

    private init() {}

    func refresh() async {
        let blacklistedIds = TicketmasterBlacklistStore.shared.blacklistedArtistIds
        guard TicketmasterAPIClient.shared.isConnected,
              let libraryId = JellyfinAPIClient.shared.selectedLibraryId,
              let allArtists = await LibraryCache.shared.items(for: "artists:\(libraryId)") else {
            artistConcerts = []
            return
        }
        // Skipped here, not just filtered out below, so a blacklisted artist doesn't cost part of
        // the free tier's daily request quota on every refresh.
        let artists = allArtists.filter { !blacklistedIds.contains($0.Id) }
        guard !artists.isEmpty else {
            artistConcerts = []
            return
        }

        artistConcerts = []
        var iterator = artists.makeIterator()
        await withTaskGroup(of: ArtistConcerts?.self) { group in
            for _ in 0..<min(Self.maxConcurrentRequests, artists.count) {
                if let artist = iterator.next() {
                    group.addTask { await Self.fetchConcerts(for: artist) }
                }
            }
            while let result = await group.next() {
                if let result {
                    artistConcerts.append(result)
                    artistConcerts.sort { ($0.nextDate ?? .distantFuture) < ($1.nextDate ?? .distantFuture) }
                }
                if let artist = iterator.next() {
                    group.addTask { await Self.fetchConcerts(for: artist) }
                }
            }
        }
    }

    /// Drops an artist from the already-loaded results immediately, so blacklisting from the Home
    /// screen or the concerts detail view takes effect right away rather than waiting for the next
    /// `refresh()`.
    func removeLocally(artistId: String) {
        artistConcerts.removeAll { $0.artistId == artistId }
    }

    private static func fetchConcerts(for artist: BaseItemDto) async -> ArtistConcerts? {
        guard let events = try? await TicketmasterAPIClient.shared.fetchUpcomingConcerts(forArtist: artist.Name), !events.isEmpty else {
            return nil
        }
        return ArtistConcerts(artistId: artist.Id, artistName: artist.Name, events: events)
    }
}
