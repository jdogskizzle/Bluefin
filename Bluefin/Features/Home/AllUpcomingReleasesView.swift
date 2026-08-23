//
//  AllUpcomingReleasesView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/23/26.
//

import SwiftUI

/// Marker route for Home's "Upcoming Releases" section header — carries no data of its own since
/// the destination just reads straight from `LidarrReleaseCache`.
struct AllUpcomingReleasesRoute: Hashable {}

/// Every upcoming Lidarr release across all followed artists, already sorted soonest-first — opened
/// from Home's "Upcoming Releases" header, since the horizontal strip there only comfortably shows a
/// handful at a time.
struct AllUpcomingReleasesView: View {
    @ObservedObject private var releaseCache = LidarrReleaseCache.shared
    @ObservedObject private var client = LidarrAPIClient.shared

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        Group {
            if releaseCache.upcomingReleases.isEmpty {
                ContentUnavailableView("No Upcoming Releases", systemImage: "opticaldisc")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(releaseCache.upcomingReleases) { release in
                            NavigationLink(value: release) {
                                releaseCell(for: release)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .avoidsMiniPlayer()
            }
        }
        .navigationTitle("Upcoming Releases")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func releaseCell(for release: LidarrCalendarItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CachedRemoteImage(url: release.coverImageURL(serverURL: client.serverURL, apiKey: client.apiKey)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(Image(systemName: "opticaldisc").foregroundStyle(.secondary))
            }
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(release.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(release.artistName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let releaseDate = release.releaseDate {
                Text(releaseDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
