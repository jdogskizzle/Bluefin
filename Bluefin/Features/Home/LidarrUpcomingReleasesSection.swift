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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(releases) { release in
                        LidarrReleaseCard(release: release)
                    }
                }
            }
        }
    }
}

struct LidarrReleaseCard: View {
    let release: LidarrCalendarItem
    @ObservedObject private var client = LidarrAPIClient.shared

    var body: some View {
        NavigationLink(value: release) {
            VStack(alignment: .leading, spacing: 4) {
                AsyncImage(url: release.coverImageURL(serverURL: client.serverURL, apiKey: client.apiKey)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.15))
                            .overlay(Image(systemName: "opticaldisc").foregroundStyle(.secondary))
                    }
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
