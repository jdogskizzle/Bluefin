//
//  NumberedSongRow.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import SwiftUI

struct NumberedSongRow: View {
    let song: BaseItemDto
    let position: Int
    var showsArtwork: Bool = false
    @ObservedObject private var player = AudioPlayerManager.shared

    private var isNowPlaying: Bool {
        player.currentItem?.Id == song.Id
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isNowPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                } else {
                    Text("\(position)")
                        .font(.subheadline)
                }
            }
            .foregroundStyle(isNowPlaying ? Color.accentColor : Color.secondary)
            .frame(width: 20, alignment: .leading)

            if showsArtwork {
                artwork
            }

            Text(song.Name)
                .font(.body)
                .foregroundStyle(isNowPlaying ? Color.accentColor : Color.primary)
                .lineLimit(1)

            Spacer()

            if let duration = song.formattedDuration {
                Text(duration)
                    .font(.footnote)
                    .foregroundStyle(isNowPlaying ? Color.accentColor : Color.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var artwork: some View {
        AsyncImage(url: JellyfinAPIClient.shared.imageURL(itemId: song.artworkItemId, maxWidth: 100)) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.15))
                .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
