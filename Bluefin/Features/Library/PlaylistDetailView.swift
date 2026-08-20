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
        _viewModel = StateObject(wrappedValue: LibraryListViewModel {
            try await JellyfinAPIClient.shared.fetchPlaylistItems(playlistId: playlist.Id)
        })
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView(
                    "Couldn't Load Playlist",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
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
                        }
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
    }

    private var header: some View {
        VStack(spacing: 8) {
            AsyncImage(url: JellyfinAPIClient.shared.imageURL(itemId: playlist.Id, maxWidth: 600)) { image in
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
                Text("\(viewModel.items.count) songs")
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
}
