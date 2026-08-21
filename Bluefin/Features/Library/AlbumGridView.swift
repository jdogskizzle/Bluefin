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
    let bannerItemId: String?
    @StateObject private var viewModel: LibraryListViewModel

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    init(title: String, subtitle: AlbumGridSubtitle, bannerItemId: String? = nil, cacheKey: String) {
        self.title = title
        self.subtitle = subtitle
        self.bannerItemId = bannerItemId
        _viewModel = StateObject(wrappedValue: LibraryListViewModel(cacheKey: cacheKey))
    }

    var body: some View {
        Group {
            if !viewModel.hasSynced {
                NotSyncedView(itemsDescription: "albums")
            } else if viewModel.items.isEmpty {
                ContentUnavailableView("No Albums", systemImage: "square.stack")
            } else {
                ScrollView {
                    if let bannerItemId {
                        banner(itemId: bannerItemId)
                    }
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
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
                .avoidsMiniPlayer()
            }
        }
        .navigationTitle(bannerItemId != nil ? "" : title)
        .navigationBarTitleDisplayMode(bannerItemId != nil ? .inline : .automatic)
        .toolbarBackground(bannerItemId != nil ? .hidden : .automatic, for: .navigationBar)
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func banner(itemId: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(itemId: itemId, imageType: "Backdrop") { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay {
                        Image(systemName: "music.mic")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding()
        }
        .frame(maxWidth: .infinity)
    }
}

struct AlbumGridCell: View {
    let album: BaseItemDto
    let subtitle: AlbumGridSubtitle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CachedAsyncImage(itemId: album.Id) { image in
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
