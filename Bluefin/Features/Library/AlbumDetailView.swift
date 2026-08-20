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

    init(album: BaseItemDto) {
        self.album = album
        _viewModel = StateObject(wrappedValue: LibraryListViewModel {
            try await JellyfinAPIClient.shared.fetchItems(
                parentId: album.Id,
                includeItemTypes: "Audio",
                recursive: false,
                sortBy: "IndexNumber"
            )
        })
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView(
                    "Couldn't Load Album",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                List {
                    Section {
                        header
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }

                    Section {
                        ForEach(viewModel.items) { song in
                            Button {
                                let index = viewModel.items.firstIndex(of: song) ?? 0
                                AudioPlayerManager.shared.play(queue: viewModel.items, startAt: index)
                            } label: {
                                AlbumSongRow(song: song)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Section {
                        footer
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
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
            AsyncImage(url: JellyfinAPIClient.shared.imageURL(itemId: album.Id, maxWidth: 600)) { image in
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
                if let artist = album.AlbumArtist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
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

struct AlbumSongRow: View {
    let song: BaseItemDto

    var body: some View {
        HStack(spacing: 12) {
            Text(song.IndexNumber.map(String.init) ?? "–")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)

            Text(song.Name)
                .font(.body)
                .lineLimit(1)

            Spacer()

            if let duration = song.formattedDuration {
                Text(duration)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
