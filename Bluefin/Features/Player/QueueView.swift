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

    /// Zips each song with its stable per-slot id and position. Identifying `ForEach` rows by that
    /// id (rather than position) is what makes a drag-reorder animate as "this row moved" instead of
    /// SwiftUI diffing it as "the content at every position from here on changed" and re-settling
    /// into place after the drop.
    private var entries: [(id: UUID, index: Int, song: BaseItemDto)] {
        Array(zip(player.queueEntryIDs, player.queue).enumerated()).map { index, pair in
            (id: pair.0, index: index, song: pair.1)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if player.queue.isEmpty {
                    ContentUnavailableView("Queue is Empty", systemImage: "list.bullet")
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(entries, id: \.id) { entry in
                                Button {
                                    AudioPlayerManager.shared.play(at: entry.index)
                                } label: {
                                    NumberedSongRow(
                                        song: entry.song,
                                        position: entry.index + 1,
                                        showsArtwork: true,
                                        isInSubqueue: player.isIndexInSubqueue(entry.index)
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(entry.index)
                                // The currently-playing (and any past) entry can't be reordered or
                                // removed — only upcoming entries, so `currentIndex` itself is never
                                // disturbed by these actions.
                                .moveDisabled(entry.index <= player.currentIndex)
                                .swipeActions(edge: .trailing) {
                                    if entry.index > player.currentIndex {
                                        Button(role: .destructive) {
                                            AudioPlayerManager.shared.removeFromQueue(at: entry.index)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                }
                            }
                            .onMove { source, destination in
                                guard let sourceIndex = source.first, source.count == 1,
                                      player.queue.indices.contains(sourceIndex),
                                      sourceIndex > player.currentIndex else { return }

                                let wasInSubqueue = player.isIndexInSubqueue(sourceIndex)
                                let movedID = player.queueEntryIDs[sourceIndex]

                                var pairs = Array(zip(player.queueEntryIDs, player.queue))
                                pairs.move(fromOffsets: source, toOffset: destination)

                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    AudioPlayerManager.shared.applyQueueReorder(
                                        newQueue: pairs.map { $0.1 },
                                        newEntryIDs: pairs.map { $0.0 },
                                        movedEntryID: movedID,
                                        wasInSubqueue: wasInSubqueue
                                    )
                                }
                            }
                        }
                        .listStyle(.plain)
                        .animation(nil, value: player.queue)
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
