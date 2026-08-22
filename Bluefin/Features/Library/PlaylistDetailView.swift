//
//  PlaylistDetailView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import SwiftUI

struct PlaylistDetailView: View {
    let playlist: BaseItemDto
    @StateObject private var viewModel: LibraryListViewModel
    @ObservedObject private var sortPreference = PlaylistSortPreference.shared
    /// Album id → release date, resolved from the synced album list rather than trusting each
    /// song's own `ProductionYear` — that field is frequently unset on individual tracks even when
    /// the album itself has a reliable release date.
    @State private var albumReleaseDates: [String: Date] = [:]

    init(playlist: BaseItemDto) {
        self.playlist = playlist
        _viewModel = StateObject(wrappedValue: LibraryListViewModel(cacheKey: "playlistSongs:\(playlist.Id)"))
    }

    /// `playlistOrder` keeps whatever order the sync produced; every other mode reorders the songs
    /// as displayed (and as `ForEach`, `PlayShuffleBar`, and "Add to Queue" all use) without
    /// touching the actual playlist on the server.
    private var sortOrderBinding: Binding<PlaylistSortOrder> {
        Binding(
            get: { sortPreference.sortOrder(for: playlist.Id) },
            set: { sortPreference.setSortOrder($0, for: playlist.Id) }
        )
    }

    private var displayedItems: [BaseItemDto] {
        switch sortPreference.sortOrder(for: playlist.Id) {
        case .playlistOrder:
            return viewModel.items
        case .artist:
            return viewModel.items.sorted { lhs, rhs in
                let lhsArtist = lhs.AlbumArtist ?? lhs.Artists?.first ?? ""
                let rhsArtist = rhs.AlbumArtist ?? rhs.Artists?.first ?? ""
                let artistComparison = lhsArtist.localizedCaseInsensitiveCompare(rhsArtist)
                if artistComparison != .orderedSame { return artistComparison == .orderedAscending }
                let lhsDate = releaseDate(for: lhs)
                let rhsDate = releaseDate(for: rhs)
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                let lhsAlbum = lhs.Album ?? ""
                let rhsAlbum = rhs.Album ?? ""
                let albumComparison = lhsAlbum.localizedCaseInsensitiveCompare(rhsAlbum)
                if albumComparison != .orderedSame { return albumComparison == .orderedAscending }
                return (lhs.IndexNumber ?? 0) < (rhs.IndexNumber ?? 0)
            }
        case .alphabetical:
            return viewModel.items.sorted { $0.Name.localizedCaseInsensitiveCompare($1.Name) == .orderedAscending }
        case .releaseDate:
            return viewModel.items.sorted { releaseDate(for: $0) < releaseDate(for: $1) }
        }
    }

    private func releaseDate(for song: BaseItemDto) -> Date {
        albumReleaseDates[song.AlbumId ?? ""] ?? .distantPast
    }

    private func loadAlbumReleaseDates() async {
        guard let libraryId = JellyfinAPIClient.shared.selectedLibraryId,
              let albums = await LibraryCache.shared.items(for: "albums:\(libraryId)") else {
            return
        }
        albumReleaseDates = Dictionary(uniqueKeysWithValues: albums.map { album in
            let date = album.premiereDate ?? album.ProductionYear.flatMap {
                Calendar(identifier: .gregorian).date(from: DateComponents(year: $0, month: 1, day: 1))
            } ?? .distantPast
            return (album.Id, date)
        })
    }

    var body: some View {
        Group {
            if !viewModel.hasSynced {
                NotSyncedView(itemsDescription: "playlist's songs")
            } else if viewModel.items.isEmpty {
                ContentUnavailableView("No Songs", systemImage: "music.note.list")
            } else {
                List {
                    Section {
                        header
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }

                    Section {
                        ForEach(Array(displayedItems.enumerated()), id: \.element.id) { index, song in
                            Button {
                                AudioPlayerManager.shared.play(queue: displayedItems, startAt: index)
                            } label: {
                                NumberedSongRow(song: song, position: index + 1, showsArtwork: true)
                            }
                            .buttonStyle(.plain)
                            .songActions(for: song, removableFrom: RemovableFromPlaylist(playlistId: playlist.Id, playlistName: playlist.Name))
                        }
                    }
                }
                .listStyle(.plain)
                .avoidsMiniPlayer()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: sortOrderBinding) {
                        Text("Playlist Order").tag(PlaylistSortOrder.playlistOrder)
                        Text("Artist").tag(PlaylistSortOrder.artist)
                        Text("Alphabetical").tag(PlaylistSortOrder.alphabetical)
                        Text("Release Date").tag(PlaylistSortOrder.releaseDate)
                    }
                    ContainerDownloadButton(songs: viewModel.items)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .task {
            await loadAlbumReleaseDates()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            CachedAsyncImage(itemId: playlist.Id) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(Image(systemName: "music.note.list").font(.largeTitle).foregroundStyle(.secondary))
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)

            VStack(spacing: 2) {
                Text(playlist.Name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text(summaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            PlayShuffleBar(songs: displayedItems)
                .padding(.horizontal, 32)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
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
