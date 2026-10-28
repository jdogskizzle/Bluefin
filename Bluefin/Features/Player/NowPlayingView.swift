//
//  NowPlayingView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import SwiftUI

struct NowPlayingView: View {
    @ObservedObject private var player = AudioPlayerManager.shared
    @ObservedObject private var favoritesStore = FavoritesStore.shared
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var showPlaylistPicker = false
    @State private var showDetails = false
    @State private var showRemoveDownloadConfirmation = false
    @State private var hasLyrics = false
    /// While the user is actively dragging the scrubber, the slider reflects this instead of
    /// `player.currentTime` — and `player.seek(to:)` is only called once, on release. Calling it on
    /// every drag tick (the naive binding) fires a full engine restart per tick, which is far heavier
    /// now than the old `AVPlayer.seek` and makes the scrubber feel unresponsive/broken while dragging.
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            if let item = player.currentItem {
                Spacer()

                artwork(for: item)

                titleRow(for: item)

                scrubber(for: item)

                HStack(spacing: 48) {
                    Button {
                        player.skipToPrevious()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title)
                    }

                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 44))
                    }

                    Button {
                        player.skipToNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title)
                    }
                }
                .foregroundStyle(.primary)

                volumeSlider

                utilityButtons
            } else {
                Spacer()
                Text("Nothing Playing")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.bottom, 24)
        .presentationDragIndicator(.visible)
        .overlay {
            ToastOverlay()
        }
        .sheet(isPresented: $showPlaylistPicker) {
            if let item = player.currentItem {
                PlaylistPickerView(song: item)
            }
        }
        .sheet(isPresented: $showDetails) {
            if let item = player.currentItem {
                SongDetailsView(song: item)
            }
        }
        .confirmRemoveDownload(songs: [player.currentItem].compactMap { $0 }, isPresented: $showRemoveDownloadConfirmation)
        .task(id: player.currentItem?.Id) {
            await checkLyricsAvailability()
        }
    }

    private func checkLyricsAvailability() async {
        guard let item = player.currentItem else {
            hasLyrics = false
            return
        }
        let lines = await CacheManager.shared.lyrics(for: item)
        hasLyrics = !lines.isEmpty
    }

    private func goToArtist(for item: BaseItemDto) async {
        guard let artistName = item.AlbumArtist ?? item.Artists?.first,
              let libraryId = JellyfinAPIClient.shared.selectedLibraryId,
              let artists = await LibraryCache.shared.items(for: "artists:\(libraryId)"),
              let artist = artists.first(where: { $0.Name == artistName }) else {
            ToastCenter.shared.show("Couldn't find that artist", isError: true)
            return
        }
        dismiss()
        AppNavigator.shared.navigate(to: .artistAlbums(artist))
    }

    private func goToAlbum(for item: BaseItemDto) async {
        guard let albumId = item.AlbumId,
              let libraryId = JellyfinAPIClient.shared.selectedLibraryId,
              let albums = await LibraryCache.shared.items(for: "albums:\(libraryId)"),
              let album = albums.first(where: { $0.Id == albumId }) else {
            ToastCenter.shared.show("Couldn't find that album", isError: true)
            return
        }
        dismiss()
        AppNavigator.shared.navigate(to: .albumSongs(album))
    }

    private func artwork(for item: BaseItemDto) -> some View {
        CachedAsyncImage(itemId: item.artworkItemId) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.15))
                .overlay(
                    Image(systemName: "music.note").font(.system(size: 60)).foregroundStyle(
                        .secondary))
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 32)
    }

    private func titleRow(for item: BaseItemDto) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Menu {
                if let artist = item.AlbumArtist ?? item.Artists?.first {
                    Button {
                        Task { await goToArtist(for: item) }
                    } label: {
                        Text("Go to Artist")
                        Text(artist)
                    }
                }
                if let album = item.Album {
                    Button {
                        Task { await goToAlbum(for: item) }
                    } label: {
                        Text("Go to Album")
                        Text(album)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.Name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let artist = item.AlbumArtist ?? item.Artists?.first {
                        Text(artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 16) {
                Button {
                    favoritesStore.toggleFavorite(item)
                } label: {
                    Image(systemName: favoritesStore.isFavorite(item.Id) ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle(favoritesStore.isFavorite(item.Id) ? Color.red : Color.primary)
                        .frame(width: 24, height: 24)
                }

                Menu {
                    SongPlaylistMenuItems(
                        song: item, showPicker: $showPlaylistPicker, showDetails: $showDetails,
                        showRemoveDownloadConfirmation: $showRemoveDownloadConfirmation, showsGoToLinks: false
                    )
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .frame(width: 24, height: 24)
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 32)
    }

    private func scrubber(for item: BaseItemDto) -> some View {
        let duration = Double(item.RunTimeTicks ?? 0) / 10_000_000
        return VStack(spacing: 4) {
            if player.isLoadingTrack {
                LoadingScrubberBar()
                    .frame(height: 20)
            } else {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubTime : player.currentTime },
                        set: { scrubTime = $0 }
                    ),
                    in: 0...max(duration, 1),
                    onEditingChanged: { editing in
                        if editing {
                            scrubTime = player.currentTime
                        }
                        isScrubbing = editing
                        if !editing {
                            player.seek(to: scrubTime)
                        }
                    }
                )
            }
            HStack {
                Text(formatted(isScrubbing ? scrubTime : player.currentTime))
                Spacer()
                Text(formatted(duration))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
    }

    private var volumeSlider: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            #if canImport(UIKit)
                VolumeSliderView()
                    .frame(height: 20)
            #endif
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
    }

    private var utilityButtons: some View {
        HStack(spacing: 72) {
            #if canImport(UIKit)
                RoutePickerView()
                    .frame(width: 24, height: 24)
            #else
                utilityButton(systemImage: "airplayaudio")
            #endif

            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
            }
            .foregroundStyle(.secondary)
            .sheet(isPresented: $showQueue) {
                QueueView()
            }

            Button {
                showLyrics = true
            } label: {
                Image(systemName: "quote.bubble")
                    .font(.title3)
            }
            .foregroundStyle(hasLyrics ? Color.secondary : Color.secondary.opacity(0.3))
            .disabled(!hasLyrics)
            .sheet(isPresented: $showLyrics) {
                LyricsView()
            }
        }
    }

    private func utilityButton(systemImage: String) -> some View {
        Button {
            // Designed later.
        } label: {
            Image(systemName: systemImage)
                .font(.title3)
        }
        .foregroundStyle(.secondary)
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Shown in place of the scrubber while `AudioPlayerManager.isLoadingTrack` is true — deliberately
/// not a real progress bar, since there's no meaningful percentage to show for a network fetch, just
/// a small segment sliding back and forth to read as "something is happening."
private struct LoadingScrubberBar: View {
    @State private var isAtTrailingEdge = false

    private let barHeight: CGFloat = 4
    private let indicatorWidthFraction: CGFloat = 0.28

    var body: some View {
        GeometryReader { geometry in
            let indicatorWidth = geometry.size.width * indicatorWidthFraction
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(Color.secondary)
                    .frame(width: indicatorWidth)
                    // `autoreverses: false` on a repeating implicit animation snaps straight back to
                    // the start each cycle instead of reversing — that's what gives the continuous
                    // one-direction "wrap" look rather than a back-and-forth bounce.
                    .offset(x: isAtTrailingEdge ? geometry.size.width : -indicatorWidth)
            }
            .clipShape(Capsule())
        }
        .frame(height: barHeight)
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                isAtTrailingEdge = true
            }
        }
    }
}
