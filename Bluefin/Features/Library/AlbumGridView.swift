//
//  AlbumGridView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import SwiftUI

enum AlbumGridSubtitle {
    case year
    case artist
}

struct AlbumGridView: View {
    let title: String
    let subtitle: AlbumGridSubtitle
    @StateObject private var viewModel: LibraryListViewModel

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    init(title: String, subtitle: AlbumGridSubtitle, fetch: @escaping () async throws -> [BaseItemDto]) {
        self.title = title
        self.subtitle = subtitle
        _viewModel = StateObject(wrappedValue: LibraryListViewModel(fetch: fetch))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView(
                    "Couldn't Load \(title)",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if viewModel.items.isEmpty {
                ContentUnavailableView("No Albums", systemImage: "square.stack")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(viewModel.items) { album in
                            NavigationLink(value: LibraryRoute.albumSongs(album)) {
                                AlbumGridCell(album: album, subtitle: subtitle)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(title)
        .task {
            await viewModel.load()
        }
    }
}

struct AlbumGridCell: View {
    let album: BaseItemDto
    let subtitle: AlbumGridSubtitle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncImage(url: JellyfinAPIClient.shared.imageURL(itemId: album.Id, maxWidth: 400)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(Image(systemName: "square.stack").foregroundStyle(.secondary))
            }
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(album.Name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(subtitleText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var subtitleText: String {
        switch subtitle {
        case .year: return album.ProductionYear.map(String.init) ?? " "
        case .artist: return album.AlbumArtist ?? " "
        }
    }
}
