//
//  PlayShuffleBar.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import SwiftUI

struct PlayShuffleBar: View {
    let songs: [BaseItemDto]

    var body: some View {
        HStack(spacing: 12) {
            Button {
                AudioPlayerManager.shared.play(queue: songs, startAt: 0)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                AudioPlayerManager.shared.play(queue: songs.shuffled(), startAt: 0)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .disabled(songs.isEmpty)
    }
}
