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
    @ObservedObject private var regionStore = TicketmasterRegionStore.shared
    @ObservedObject private var concertCache = TicketmasterConcertCache.shared
    /// Ephemeral — plain view state, never written to `TicketmasterRegionStore` or anywhere else, so
    /// it has no effect once this view closes. Lets someone browsing with a region filter set peek
    /// at the rest of a tour without changing that filter.
    @State private var showingAllLocations = false

    private var allEvents: [TicketmasterEvent] {
        concertCache.rawEvents(forArtistId: concerts.artistId) ?? concerts.events
    }

    private var displayedEvents: [TicketmasterEvent] {
        showingAllLocations ? allEvents : concerts.events
    }

    private var hasAdditionalLocations: Bool {
        regionStore.selectedRegion != nil && allEvents.count > concerts.events.count
    }

    var body: some View {
        List {
            if hasHeaderContent {
                Section {
                    header
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
            }

            if hasAdditionalLocations, let regionName = regionStore.selectedRegion?.name {
                Section {
                    Button {
                        withAnimation { showingAllLocations.toggle() }
                    } label: {
                        Text(showingAllLocations ? "Show \(regionName)" : "Show All Locations")
                    }
                }
            }

            Section {
                ForEach(displayedEvents) { event in
                    if let url = event.eventURL {
                        Link(destination: url) {
                            row(for: event)
                        }
                        .foregroundStyle(.primary)
                    } else {
                        row(for: event)
                    }
                }
            } footer: {
                Text("\(displayedEvents.count) show\(displayedEvents.count == 1 ? "" : "s")")
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

    private var hasHeaderContent: Bool {
        concerts.events.first?.imageURL != nil || concerts.tourName != nil
    }

    private var header: some View {
        VStack(spacing: 8) {
            if let imageURL = concerts.events.first?.imageURL {
                CachedRemoteImage(url: imageURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.secondary.opacity(0.15))
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }

            if let tourName = concerts.tourName {
                Text(tourName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func row(for event: TicketmasterEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let date = event.date {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                if let statusLabel = event.statusLabel {
                    Spacer()
                    Text(statusLabel)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                }
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
            if let priceRangeText = event.priceRangeText {
                Text(priceRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
