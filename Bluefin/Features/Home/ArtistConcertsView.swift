//
//  ArtistConcertsView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/23/26.
//

import SwiftUI

/// Every upcoming tour stop for one artist, soonest first — tapping a row opens the event's
/// Ticketmaster page (there's no in-app purchase flow, so this is as far as Bluefin itself goes).
struct ArtistConcertsView: View {
    let concerts: ArtistConcerts

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(concerts.events) { event in
            if let url = event.eventURL {
                Link(destination: url) {
                    row(for: event)
                }
                .foregroundStyle(.primary)
            } else {
                row(for: event)
            }
        }
        .avoidsMiniPlayer()
        .navigationTitle(concerts.artistName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        TicketmasterBlacklistStore.shared.blacklist(artistId: concerts.artistId, artistName: concerts.artistName)
                        TicketmasterConcertCache.shared.removeLocally(artistId: concerts.artistId)
                        dismiss()
                    } label: {
                        Label("Hide from Upcoming Concerts", systemImage: "eye.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func row(for event: TicketmasterEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let date = event.date {
                Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            if let venueName = event.venueName {
                Text(venueName)
                    .font(.body)
            }
            let location = [event.city, event.stateCode].compactMap { $0 }.joined(separator: ", ")
            if !location.isEmpty {
                Text(location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
