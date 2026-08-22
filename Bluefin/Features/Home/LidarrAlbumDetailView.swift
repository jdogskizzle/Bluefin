//
//  LidarrAlbumDetailView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/21/26.
//

import SwiftUI

/// Shows the track listing Lidarr already knows about for an upcoming/unreleased album. The album
/// isn't in the Jellyfin library yet, so there's no audio to play — rows are plain (non-tappable,
/// no swipe/context actions) and rendered at reduced opacity to read as unavailable rather than
/// implying they behave like a normal song row elsewhere in the app.
struct LidarrAlbumDetailView: View {
    let release: LidarrCalendarItem
    @ObservedObject private var client = LidarrAPIClient.shared
    @State private var tracks: [LidarrTrack] = []
    @State private var isLoading = true
    @State private var artist: BaseItemDto?

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }

            Section {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if tracks.isEmpty {
                    Text("No track list available yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tracks) { track in
                        trackRow(track)
                    }
                }
            } footer: {
                Text("This album isn't in your library yet, so it can't be played.")
            }
        }
        .listStyle(.plain)
        .avoidsMiniPlayer()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadTracks()
        }
        .task {
            await resolveArtist()
        }
    }

    @ViewBuilder
    private var header: some View {
        if let artist {
            artworkAndTitle
                .contentShape(Rectangle())
                .onTapGesture {
                    AppNavigator.shared.navigate(to: .artistAlbums(artist))
                }
        } else {
            artworkAndTitle
        }
    }

    private var artworkAndTitle: some View {
        VStack(spacing: 8) {
            AsyncImage(url: release.coverImageURL(serverURL: client.serverURL, apiKey: client.apiKey)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                        .overlay(Image(systemName: "opticaldisc").font(.largeTitle).foregroundStyle(.secondary))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)

            VStack(spacing: 2) {
                Text(release.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text(release.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let releaseDate = release.releaseDate {
                    Text("Releases \(releaseDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func resolveArtist() async {
        guard let libraryId = JellyfinAPIClient.shared.selectedLibraryId,
              let artists = await LibraryCache.shared.items(for: "artists:\(libraryId)") else {
            return
        }
        artist = artists.first { $0.Name == release.artistName }
    }

    private func trackRow(_ track: LidarrTrack) -> some View {
        HStack(spacing: 12) {
            Text(track.trackNumber ?? "")
                .font(.subheadline)
                .frame(width: 24, alignment: .trailing)

            Text(track.title)
                .font(.body)
                .lineLimit(1)

            Spacer()

            if let duration = track.formattedDuration {
                Text(duration)
                    .font(.subheadline)
            }
        }
        .foregroundStyle(.secondary)
        .opacity(0.5)
    }

    private func loadTracks() async {
        isLoading = true
        tracks = (try? await client.fetchTracks(albumId: release.id)) ?? []
        isLoading = false
    }
}
