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

    init(playlist: BaseItemDto) {
        self.playlist = playlist
        _viewModel = StateObject(wrappedValue: LibraryListViewModel(cacheKey: "playlistSongs:\(playlist.Id)"))
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
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, song in
                            Button {
                                AudioPlayerManager.shared.play(queue: viewModel.items, startAt: index)
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
                    ContainerDownloadButton(songs: viewModel.items)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await viewModel.load()
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

            PlayShuffleBar(songs: viewModel.items)
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
