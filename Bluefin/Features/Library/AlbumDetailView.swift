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
    @State private var showRemoveDownloadConfirmation = false

    init(album: BaseItemDto) {
        self.album = album
        _viewModel = StateObject(wrappedValue: LibraryListViewModel(cacheKey: "albumSongs:\(album.Id)"))
    }

    private struct DiscGroup: Identifiable {
        let discNumber: Int
        var songs: [(flatIndex: Int, song: BaseItemDto)] = []
        var id: Int { discNumber }
    }

    /// Consecutive runs of `viewModel.items` grouped by disc — songs are already sorted disc-then-
    /// track by the library sync, so this is just splitting on where the disc number changes. Each
    /// entry keeps its `flatIndex` in the underlying (ungrouped) list, since that's what
    /// `AudioPlayerManager.play(queue:startAt:)` needs — the play queue itself stays one flat list.
    private var discGroups: [DiscGroup] {
        var result: [DiscGroup] = []
        for (flatIndex, song) in viewModel.items.enumerated() {
            if let lastIndex = result.indices.last, result[lastIndex].discNumber == song.discNumber {
                result[lastIndex].songs.append((flatIndex, song))
            } else {
                result.append(DiscGroup(discNumber: song.discNumber, songs: [(flatIndex, song)]))
            }
        }
        return result
    }

    private var hasMultipleDiscs: Bool {
        discGroups.count > 1
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
                        ForEach(discGroups) { group in
                            if hasMultipleDiscs {
                                Text("Disc \(group.discNumber)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                    .listRowSeparator(.hidden)
                            }
                            ForEach(Array(group.songs.enumerated()), id: \.element.song.id) { discPosition, entry in
                                Button {
                                    AudioPlayerManager.shared.play(queue: viewModel.items, startAt: entry.flatIndex)
                                } label: {
                                    NumberedSongRow(song: entry.song, position: discPosition + 1)
                                }
                                .buttonStyle(.plain)
                                .songActions(for: entry.song, isAlbumContext: true)
                            }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        AudioPlayerManager.shared.addToSubqueue(viewModel.items)
                    } label: {
                        Label("Add to Queue", systemImage: "text.insert")
                    }
                    ContainerDownloadButton(
                        songs: viewModel.items,
                        group: DownloadGroupInfo(id: album.Id, kind: .album, name: album.Name),
                        showRemoveConfirmation: $showRemoveDownloadConfirmation
                    )
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmRemoveDownload(
            songs: viewModel.items,
            group: DownloadGroupInfo(id: album.Id, kind: .album, name: album.Name),
            isPresented: $showRemoveDownloadConfirmation
        )
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

    @ViewBuilder
    private var artistLink: some View {
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
