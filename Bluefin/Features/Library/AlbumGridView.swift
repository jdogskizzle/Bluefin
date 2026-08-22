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
    @ObservedObject private var sortPreference = AlbumSortPreference.shared
    @ObservedObject private var releaseCache = LidarrReleaseCache.shared
    @State private var artistSongs: [BaseItemDto] = []

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    /// Only an artist's own albums page (identified by having a banner) sorts by release date —
    /// the plain top-level Albums grid keeps whatever order the sync produced.
    private var isArtistPage: Bool { bannerItemId != nil }

    private var displayedItems: [BaseItemDto] {
        guard isArtistPage else { return viewModel.items }
        return viewModel.items.sorted { lhs, rhs in
            let lhsDate = releaseDateKey(for: lhs)
            let rhsDate = releaseDateKey(for: rhs)
            guard lhsDate != rhsDate else {
                // Same key (e.g. neither has any date info at all) — fall back to name so the
                // order is at least deterministic rather than whatever the sync happened to store.
                return lhs.Name < rhs.Name
            }
            return sortPreference.sortOrder == .releaseDateAscending ? lhsDate < rhsDate : lhsDate > rhsDate
        }
    }

    /// The precise `premiereDate` when available; otherwise January 1st of `ProductionYear` as a
    /// coarser fallback, so albums missing a precise date still land in roughly the right place
    /// rather than being pushed to one end of the list. `ProductionYear` alone isn't precise enough
    /// on its own — two albums released in the same year would otherwise tie and fall back to
    /// whatever order the sync happened to store them in.
    private var artistUpcomingReleases: [LidarrCalendarItem] {
        guard isArtistPage else { return [] }
        return releaseCache.upcomingReleases.filter { $0.artistName == title }
    }

    private func releaseDateKey(for album: BaseItemDto) -> Date {
        if let premiereDate = album.premiereDate {
            return premiereDate
        }
        if let year = album.ProductionYear {
            return Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: 1, day: 1)) ?? .distantPast
        }
        return .distantPast
    }

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
                    if !artistUpcomingReleases.isEmpty {
                        LidarrUpcomingReleasesSection(title: "Upcoming Releases", releases: artistUpcomingReleases)
                            .padding(.horizontal)
                            .padding(.top, 12)
                    }
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(displayedItems) { album in
                            NavigationLink(value: LibraryRoute.albumSongs(album)) {
                                AlbumGridCell(album: album, subtitle: subtitle)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: bannerItemId != nil ? .top : [])
                .avoidsMiniPlayer()
            }
        }
        .navigationTitle(bannerItemId != nil ? "" : title)
        .navigationBarTitleDisplayMode(bannerItemId != nil ? .inline : .automatic)
        .toolbarBackground(bannerItemId != nil ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            if isArtistPage {
                ToolbarItem(placement: .topBarTrailing) {
                    artistMenu
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .task {
            await loadArtistSongs()
        }
    }

    private var artistMenu: some View {
        Menu {
            Picker("Sort", selection: $sortPreference.sortOrder) {
                Text("Release Date (Oldest First)").tag(AlbumSortOrder.releaseDateAscending)
                Text("Release Date (Newest First)").tag(AlbumSortOrder.releaseDateDescending)
            }
            ContainerDownloadButton(songs: artistSongs)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func loadArtistSongs() async {
        guard isArtistPage, let libraryId = JellyfinAPIClient.shared.selectedLibraryId,
              let songs = await LibraryCache.shared.items(for: "songs:\(libraryId)") else {
            return
        }
        artistSongs = songs.filter { $0.AlbumArtist == title }
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
