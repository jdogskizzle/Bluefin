//
//  AlbumDetailView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import SwiftUI

struct AlbumDetailView: View {
    let album: BaseItemDto
    @StateObject private var viewModel: LibraryListViewModel
    @State private var artist: BaseItemDto?

    init(album: BaseItemDto) {
        self.album = album
        _viewModel = StateObject(wrappedValue: LibraryListViewModel(cacheKey: "albumSongs:\(album.Id)"))
    }

    var body: some View {
        Group {
            if !viewModel.hasSynced {
                NotSyncedView(itemsDescription: "album's songs")
            } else {
                List {
                    Section {
                        header
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }

                    Section {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, song in
                            Button {
                                AudioPlayerManager.shared.play(queue: viewModel.items, startAt: index)
                            } label: {
                                NumberedSongRow(song: song, position: index + 1)
                            }
                            .buttonStyle(.plain)
                            .songActions(for: song, isAlbumContext: true)
                        }
                    }

                    Section {
                        footer
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .avoidsMiniPlayer()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .task {
            await resolveArtist()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            artistLink

            PlayShuffleBar(songs: viewModel.items)
                .padding(.horizontal, 32)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    /// Artwork + title + artist name, tapping through to the artist's page — once `artist` has
    /// resolved (see `resolveArtist()`; the album record itself only carries the artist's *name*,
    /// not an id, so it's looked up from the synced `LibraryCache` artist list). Falls back to
    /// plain, non-interactive content if there's no artist name or the lookup doesn't find a match.
    @ViewBuilder
    private var artistLink: some View {
        if let artist {
            // A `NavigationLink` used directly as row content gets an automatic disclosure chevron
            // from `List` — not wanted on this header. Keeping the visible content plain and driving
            // the actual navigation from an invisible `NavigationLink` behind it (sized to match via
            // `Color.clear`) avoids that while still pushing to the artist's page on tap.
            artworkAndTitle
                .background {
                    NavigationLink(value: LibraryRoute.artistAlbums(artist)) {
                        Color.clear
                    }
                    .opacity(0)
                }
        } else {
            artworkAndTitle
        }
    }

    private var artworkAndTitle: some View {
        VStack(spacing: 8) {
            CachedAsyncImage(itemId: album.Id) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(Image(systemName: "square.stack").font(.largeTitle).foregroundStyle(.secondary))
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)

            VStack(spacing: 2) {
                Text(album.Name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                if let artistName = album.AlbumArtist {
                    Text(artistName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }

    private func resolveArtist() async {
        guard let artistName = album.AlbumArtist,
              let libraryId = JellyfinAPIClient.shared.selectedLibraryId,
              let artists = await LibraryCache.shared.items(for: "artists:\(libraryId)") else {
            return
        }
        artist = artists.first { $0.Name == artistName }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let year = album.ProductionYear {
                Text(String(year))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(summaryText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var summaryText: String {
        let count = viewModel.items.count
        let songLabel = count == 1 ? "song" : "songs"
        let totalTicks = viewModel.items.compactMap { $0.RunTimeTicks }.reduce(0, +)
        let totalSeconds = Int(totalTicks / 10_000_000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let durationText = hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"
        return "\(count) \(songLabel), \(durationText)"
    }
}
