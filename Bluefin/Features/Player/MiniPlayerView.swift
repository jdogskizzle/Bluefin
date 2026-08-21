//
//  MiniPlayerView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject private var player = AudioPlayerManager.shared
    @State private var showNowPlaying = false

    var body: some View {
        if let item = player.currentItem {
            HStack(spacing: 12) {
                CachedAsyncImage(itemId: item.artworkItemId) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.Name)
                        .font(.subheadline)
                        .lineLimit(1)
                    if let artist = item.AlbumArtist ?? item.Artists?.first {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)

                Button {
                    player.skipToNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .contentShape(Rectangle())
            .onTapGesture {
                showNowPlaying = true
            }
            .sheet(isPresented: $showNowPlaying) {
                NowPlayingView()
            }
        }
    }
}

extension MiniPlayerView {
    /// Total rendered height of the floating pill: 36pt artwork + 10pt vertical padding on each side.
    static let height: CGFloat = 56

    /// Vertical gap between the pill's bottom edge and the tab bar below it, as applied in MainTabView.
    static let tabBarGap: CGFloat = 60

    /// Total space to reserve at the bottom of scrollable content so it clears the floating pill.
    static let reservedHeight: CGFloat = height + tabBarGap
}

private struct AvoidsMiniPlayerModifier: ViewModifier {
    @ObservedObject private var player = AudioPlayerManager.shared

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if player.currentItem != nil {
                Color.clear.frame(height: MiniPlayerView.reservedHeight)
            }
        }
    }
}

extension View {
    /// Reserves space at the bottom of scrollable content so it isn't hidden behind the floating mini-player.
    func avoidsMiniPlayer() -> some View {
        modifier(AvoidsMiniPlayerModifier())
    }
}
