//
//  TicketmasterBlacklistStore.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/23/26.
//

import Combine
import Foundation

/// An artist the user has chosen to never see in Upcoming Concerts, even if Ticketmaster has tour
/// dates for them — the name is stored alongside the id (same reasoning as `PinnedPlaylistStore`) so
/// the blacklist management page can list it without an async library lookup.
struct BlacklistedArtist: Identifiable, Hashable, Codable {
    let id: String
    let name: String
}

/// Persists which artists are excluded from `TicketmasterConcertCache`'s results — checked before
/// ever making a Ticketmaster request for an artist, so a blacklisted artist doesn't just get hidden
/// from the UI, it isn't searched for at all (saving a share of the free tier's daily quota).
@MainActor
final class TicketmasterBlacklistStore: ObservableObject {
    static let shared = TicketmasterBlacklistStore()

    @Published private(set) var blacklistedArtists: [BlacklistedArtist] = []

    private static let defaultsKey = "com.bluefin.ticketmaster.blacklistedArtists"

    private init() {
        load()
    }

    var blacklistedArtistIds: Set<String> {
        Set(blacklistedArtists.map(\.id))
    }

    func isBlacklisted(_ artistId: String) -> Bool {
        blacklistedArtistIds.contains(artistId)
    }

    func blacklist(artistId: String, artistName: String) {
        guard !isBlacklisted(artistId) else { return }
        blacklistedArtists.append(BlacklistedArtist(id: artistId, name: artistName))
        blacklistedArtists.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save()
    }

    func removeFromBlacklist(_ artistId: String) {
        blacklistedArtists.removeAll { $0.id == artistId }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([BlacklistedArtist].self, from: data) else {
            return
        }
        blacklistedArtists = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(blacklistedArtists) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
