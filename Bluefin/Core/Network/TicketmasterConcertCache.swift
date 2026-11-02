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
struct ArtistConcerts: Identifiable, Hashable, Codable {
    let artistId: String
    let artistName: String
    let events: [TicketmasterEvent]

    var id: String { artistId }
    var nextDate: Date? { events.first?.date }

    /// Ticketmaster has no dedicated "tour name" field, but almost every date on the same tour
    /// shares an identical event name (e.g. "Billie Eilish: HIT ME HARD AND SOFT: THE TOUR") — the
    /// most common name across this artist's shows is a reliable stand-in, shown at the top of
    /// `ArtistConcertsView`. `nil` when it's indistinguishable from the artist's own name (a small
    /// local show with no real "tour" branding), so that page doesn't show a redundant duplicate.
    var tourName: String? {
        let counts = Dictionary(grouping: events, by: \.name).mapValues(\.count)
        guard let mostCommon = counts.max(by: { $0.value < $1.value })?.key,
              Self.normalizedForComparison(mostCommon) != Self.normalizedForComparison(artistName) else {
            return nil
        }
        return mostCommon
    }

    private static func normalizedForComparison(_ string: String) -> String {
        string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Upcoming concerts for every artist in the synced library, fetched together up front (once per app
/// session, triggered from `HomeView`) the same way `LidarrReleaseCache` fetches releases — so
/// opening the concerts list for one artist later just reads from here instead of making its own
/// network round trip.
///
/// Also persisted to disk, same reasoning as `LidarrReleaseCache`: a refresh can fail (no network at
/// all, Ticketmaster briefly down, etc.), and without persistence that would blank "Upcoming
/// Concerts" on every such launch even though nothing about the concerts actually changed.
@MainActor
final class TicketmasterConcertCache: ObservableObject {
    static let shared = TicketmasterConcertCache()

    /// Every fetched artist's full, worldwide set of upcoming events, unfiltered by region —
    /// `artistConcerts` is derived from this by `applyRegionFilter()`, so switching the region in
    /// settings is instant and never needs to re-hit Ticketmaster.
    private var rawArtistConcerts: [ArtistConcerts] = []

    @Published private(set) var artistConcerts: [ArtistConcerts] = []

    /// Set once a fetch has actually completed for the current connection. `HomeView`'s `.task`
    /// re-runs `refresh()` every time it reappears — SwiftUI can tear down and rebuild an inactive
    /// tab's view hierarchy, which restarts `.task` modifiers even though nothing actually changed —
    /// so without this guard, switching tabs and back would silently re-fetch every artist from
    /// Ticketmaster again on every visit. `refresh(force:)` bypasses it for an explicit pull-to-refresh.
    private var hasLoaded = false

    /// Ticketmaster's free-tier API key enforces roughly 5 requests/second — searching every library
    /// artist at once would burst well past that and mostly come back as rate-limit errors, so this
    /// caps how many run concurrently instead.
    private static let maxConcurrentRequests = 4

    private static let defaultsKey = "com.bluefin.ticketmasterConcertCache"

    private init() {
        loadPersisted()
    }

    func refresh(force: Bool = false) async {
        guard TicketmasterAPIClient.shared.isConnected else {
            hasLoaded = false
            rawArtistConcerts = []
            artistConcerts = []
            clearPersisted()
            return
        }
        guard force || !hasLoaded else { return }

        // Each of these just means "nothing to fetch yet" (library not synced, every artist
        // blacklisted) rather than an actual failure, but either way there's nothing new to show —
        // leave whatever's already on screen (persisted or from an earlier refresh) rather than
        // blanking it.
        guard let libraryId = JellyfinAPIClient.shared.selectedLibraryId,
              let allArtists = await LibraryCache.shared.items(for: "artists:\(libraryId)") else {
            return
        }
        // Skipped here, not just filtered out below, so a blacklisted artist doesn't cost part of
        // the free tier's daily request quota on every refresh.
        let blacklistedIds = TicketmasterBlacklistStore.shared.blacklistedArtistIds
        let artists = allArtists.filter { !blacklistedIds.contains($0.Id) }
        guard !artists.isEmpty else { return }

        hasLoaded = true
        var fetchedConcerts: [ArtistConcerts] = []
        var iterator = artists.makeIterator()
        await withTaskGroup(of: ArtistConcerts?.self) { group in
            for _ in 0..<min(Self.maxConcurrentRequests, artists.count) {
                if let artist = iterator.next() {
                    group.addTask { await Self.fetchConcerts(for: artist) }
                }
            }
            while let result = await group.next() {
                if let result {
                    fetchedConcerts.append(result)
                }
                if let artist = iterator.next() {
                    group.addTask { await Self.fetchConcerts(for: artist) }
                }
            }
        }
        rawArtistConcerts = fetchedConcerts
        applyRegionFilter()
        persist()
    }

    /// Recomputes `artistConcerts` from `rawArtistConcerts` against the currently selected region —
    /// each artist's events are narrowed to that region first (so `nextDate`, and therefore the sort
    /// order, reflects the soonest show *in that region*), and an artist left with no matching shows
    /// drops out entirely rather than showing with an empty tour.
    func applyRegionFilter() {
        let region = TicketmasterRegionStore.shared.selectedRegion
        artistConcerts = rawArtistConcerts
            .compactMap { artist -> ArtistConcerts? in
                let matchingEvents = artist.events.filter { Self.matches($0, region: region) }
                guard !matchingEvents.isEmpty else { return nil }
                return ArtistConcerts(artistId: artist.artistId, artistName: artist.artistName, events: matchingEvents)
            }
            .sorted { ($0.nextDate ?? .distantFuture) < ($1.nextDate ?? .distantFuture) }
    }

    /// The full, worldwide event list for one artist, ignoring the current region filter — backs
    /// `ArtistConcertsView`'s ephemeral "Show All Locations" toggle, which needs to look past the
    /// filter without changing it (that toggle is plain view `@State`, never written here or
    /// anywhere else, so it has no lasting effect on `artistConcerts`).
    func rawEvents(forArtistId artistId: String) -> [TicketmasterEvent]? {
        rawArtistConcerts.first { $0.artistId == artistId }?.events
    }

    /// Drops an artist from the already-loaded results immediately, so blacklisting from the Home
    /// screen or the concerts detail view takes effect right away rather than waiting for the next
    /// `refresh()`.
    func removeLocally(artistId: String) {
        rawArtistConcerts.removeAll { $0.artistId == artistId }
        artistConcerts.removeAll { $0.artistId == artistId }
        persist()
    }

    private func loadPersisted() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let persisted = try? JSONDecoder().decode([ArtistConcerts].self, from: data) else { return }
        rawArtistConcerts = persisted
        applyRegionFilter()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(rawArtistConcerts) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private func clearPersisted() {
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }

    private static func matches(_ event: TicketmasterEvent, region: TicketmasterRegion?) -> Bool {
        guard let region else { return true }
        switch region.kind {
        case .usState:
            return event.countryCode == "US" && event.stateCode == region.code
        case .canadaProvince:
            return event.countryCode == "CA" && event.stateCode == region.code
        case .country:
            return event.countryCode == region.code
        }
    }

    private static func fetchConcerts(for artist: BaseItemDto) async -> ArtistConcerts? {
        guard let events = try? await TicketmasterAPIClient.shared.fetchUpcomingConcerts(forArtist: artist.Name), !events.isEmpty else {
            return nil
        }
        return ArtistConcerts(artistId: artist.Id, artistName: artist.Name, events: events)
    }
}
