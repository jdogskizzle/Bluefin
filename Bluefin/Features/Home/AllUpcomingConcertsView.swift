//
//  AllUpcomingConcertsView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/23/26.
//

import SwiftUI

/// Marker route for Home's "Upcoming Concerts" section header — carries no data of its own since
/// the destination just reads straight from `TicketmasterConcertCache`.
struct AllUpcomingConcertsRoute: Hashable {}

/// Every artist with upcoming concerts (after the region filter and blacklist), sorted soonest-first
/// — opened from Home's "Upcoming Concerts" header, since the horizontal strip there only
/// comfortably shows a handful at a time. A plain list of rows (matching `ArtistListView`'s look),
/// not a grid — a concert entry is really about the date/venue text, which a card-style layout has
/// less room for than a row does.
struct AllUpcomingConcertsView: View {
    @ObservedObject private var concertCache = TicketmasterConcertCache.shared

    var body: some View {
        Group {
            if concertCache.artistConcerts.isEmpty {
                ContentUnavailableView("No Upcoming Concerts", systemImage: "music.mic")
            } else {
                List(concertCache.artistConcerts) { concerts in
                    NavigationLink(value: concerts) {
                        row(for: concerts)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            TicketmasterBlacklistStore.shared.blacklist(artistId: concerts.artistId, artistName: concerts.artistName)
                            TicketmasterConcertCache.shared.removeLocally(artistId: concerts.artistId)
                        } label: {
                            Label("Hide from Upcoming Concerts", systemImage: "eye.slash")
                        }
                    }
                }
                .avoidsMiniPlayer()
            }
        }
        .navigationTitle("Upcoming Concerts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for concerts: ArtistConcerts) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(itemId: concerts.artistId) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: "music.mic")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(concerts.artistName)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                let subtitle = subtitleText(for: concerts)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func subtitleText(for concerts: ArtistConcerts) -> String {
        var parts: [String] = []
        if let nextDate = concerts.nextDate {
            parts.append(nextDate.formatted(.dateTime.month(.abbreviated).day().year()))
        }
        if concerts.events.count > 1 {
            parts.append("\(concerts.events.count) shows")
        }
        return parts.joined(separator: " · ")
    }
}
