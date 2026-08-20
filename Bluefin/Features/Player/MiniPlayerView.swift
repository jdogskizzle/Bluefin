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
            Button {
                showNowPlaying = true
            } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: JellyfinAPIClient.shared.imageURL(itemId: item.artworkItemId, maxWidth: 100)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                            .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
                    }
                    .frame(width: 40, height: 40)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showNowPlaying) {
                NowPlayingView()
            }
        }
    }
}
