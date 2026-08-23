//
//  TicketmasterUpcomingConcertsSection.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/23/26.
//

import SwiftUI

/// A horizontal strip of artists with upcoming concerts, sorted by the soonest tour date — mirrors
/// `LidarrUpcomingReleasesSection`'s layout, but keyed by artist (each card opens every stop on that
/// artist's tour) rather than by individual album.
struct TicketmasterUpcomingConcertsSection: View {
    let artistConcerts: [ArtistConcerts]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Upcoming Concerts")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(artistConcerts) { concerts in
                        ArtistConcertsCard(concerts: concerts)
                    }
                }
            }
        }
    }
}

private struct ArtistConcertsCard: View {
    let concerts: ArtistConcerts

    var body: some View {
        NavigationLink(value: concerts) {
            VStack(alignment: .leading, spacing: 4) {
                CachedAsyncImage(itemId: concerts.artistId) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                        .overlay(Image(systemName: "music.mic").foregroundStyle(.secondary))
                }
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(concerts.artistName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let nextDate = concerts.nextDate {
                    Text(nextDate.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if concerts.events.count > 1 {
                    Text("\(concerts.events.count) shows")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120)
        }
        .buttonStyle(.plain)
    }
}
