//
//  QueueView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Combine
import SwiftUI

struct QueueView: View {
    @ObservedObject private var player = AudioPlayerManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if player.queue.isEmpty {
                    ContentUnavailableView("Queue is Empty", systemImage: "list.bullet")
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(Array(player.queue.enumerated()), id: \.offset) { index, song in
                                Button {
                                    AudioPlayerManager.shared.play(at: index)
                                } label: {
                                    NumberedSongRow(song: song, position: index + 1, showsArtwork: true)
                                }
                                .buttonStyle(.plain)
                                .id(index)
                            }
                        }
                        .listStyle(.plain)
                        .onAppear {
                            proxy.scrollTo(player.currentIndex, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
    }
}
