//
//  LidarrUpcomingReleasesSection.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/21/26.
//

import SwiftUI

/// A horizontal strip of upcoming Lidarr releases — used on Home (all followed artists) and on an
/// artist's own album page (that one artist's releases only).
struct LidarrUpcomingReleasesSection: View {
    let title: String
    let releases: [LidarrCalendarItem]
    /// Only the Home screen's own (all-followed-artists) section links to the full grid — an
    /// artist's own album page reuses this same component for just that artist's releases, where a
    /// "see all" pointing at every artist's releases would be a non sequitur.
    var showsSeeAllLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(releases) { release in
                        LidarrReleaseCard(release: release)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if showsSeeAllLink {
            NavigationLink(value: AllUpcomingReleasesRoute()) {
                headerLabel
            }
            .buttonStyle(.plain)
        } else {
            headerLabel
        }
    }

    private var headerLabel: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            if showsSeeAllLink {
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

struct LidarrReleaseCard: View {
    let release: LidarrCalendarItem
    @ObservedObject private var client = LidarrAPIClient.shared

    var body: some View {
        NavigationLink(value: release) {
            VStack(alignment: .leading, spacing: 4) {
                CachedRemoteImage(url: release.coverImageURL(serverURL: client.serverURL, apiKey: client.apiKey)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                        .overlay(Image(systemName: "opticaldisc").foregroundStyle(.secondary))
                }
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(release.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(release.artistName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let releaseDate = release.releaseDate {
                    Text(releaseDate.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120)
        }
        .buttonStyle(.plain)
    }
}
