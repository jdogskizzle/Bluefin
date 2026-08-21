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
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var showPlaylistPicker = false
    @State private var hasLyrics = false

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
            VStack(alignment: .leading, spacing: 4) {
                Text(item.Name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(2)
                if let artist = item.AlbumArtist ?? item.Artists?.first {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 16) {
                Button {
                    // Favorite — designed later.
                } label: {
                    Image(systemName: "heart")
                        .font(.title3)
                        .frame(width: 24, height: 24)
                }

                Menu {
                    SongPlaylistMenuItems(song: item, showPicker: $showPlaylistPicker)
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
            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(duration, 1)
            )
            HStack {
                Text(formatted(player.currentTime))
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
