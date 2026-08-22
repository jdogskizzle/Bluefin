//
//  PlaylistDetailView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import PhotosUI
import SwiftUI
import UIKit

struct PlaylistDetailView: View {
    let playlist: BaseItemDto
    @StateObject private var viewModel: LibraryListViewModel
    @ObservedObject private var sortPreference = PlaylistSortPreference.shared
    /// Album id → release date, resolved from the synced album list rather than trusting each
    /// song's own `ProductionYear` — that field is frequently unset on individual tracks even when
    /// the album itself has a reliable release date.
    @State private var albumReleaseDates: [String: Date] = [:]
    @State private var displayName: String
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var imageVersion = UUID()

    init(playlist: BaseItemDto) {
        self.playlist = playlist
        _viewModel = StateObject(wrappedValue: LibraryListViewModel(cacheKey: "playlistSongs:\(playlist.Id)"))
        _displayName = State(initialValue: playlist.Name)
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
                            .songActions(for: song, removableFrom: RemovableFromPlaylist(playlistId: playlist.Id, playlistName: displayName))
                        }
                        .onMove(perform: moveHandler)
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
                    Button {
                        renameText = displayName
                        showRenameAlert = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Change Image", systemImage: "photo")
                    }
                    Button {
                        AudioPlayerManager.shared.addToSubqueue(displayedItems)
                    } label: {
                        Label("Add to Queue", systemImage: "text.insert")
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
        .alert("Rename Playlist", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let newName = renameText
                displayName = newName
                PlaylistActionService.renamePlaylist(playlist, newName: newName)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task { await applyNewImage(newItem) }
        }
    }

    /// Reordering only makes sense (and is only offered) while viewing the playlist's real,
    /// server-side order — dragging a row in a sorted view wouldn't map to a meaningful position.
    private var moveHandler: ((IndexSet, Int) -> Void)? {
        guard sortPreference.sortOrder(for: playlist.Id) == .playlistOrder else { return nil }
        return moveSongs
    }

    private func moveSongs(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        let song = viewModel.items[sourceIndex]
        viewModel.items.move(fromOffsets: source, toOffset: destination)
        guard let newIndex = viewModel.items.firstIndex(where: { ($0.PlaylistItemId ?? $0.Id) == (song.PlaylistItemId ?? song.Id) }) else { return }
        PlaylistActionService.moveSong(song, toIndex: newIndex, in: playlist.Id, newOrder: viewModel.items)
    }

    private func applyNewImage(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data),
              let jpegData = uiImage.jpegData(compressionQuality: 0.85) else { return }
        selectedPhotoItem = nil
        let succeeded = await PlaylistActionService.updatePlaylistImage(playlist, imageData: jpegData, mimeType: "image/jpeg")
        if succeeded {
            imageVersion = UUID()
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
            .id(imageVersion)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)

            VStack(spacing: 2) {
                Text(displayName)
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
