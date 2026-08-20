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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let item = player.currentItem {
                    artwork(for: item)

                    VStack(spacing: 4) {
                        Text(item.Name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        if let artist = item.AlbumArtist ?? item.Artists?.first {
                            Text(artist)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)

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

                    Spacer()
                } else {
                    Spacer()
                    Text("Nothing Playing")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.top, 24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func artwork(for item: BaseItemDto) -> some View {
        AsyncImage(url: JellyfinAPIClient.shared.imageURL(itemId: item.artworkItemId, maxWidth: 600)) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.15))
                .overlay(Image(systemName: "music.note").font(.system(size: 60)).foregroundStyle(.secondary))
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
