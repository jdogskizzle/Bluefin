//
//  LyricsView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Combine
import SwiftUI

struct LyricsView: View {
    @ObservedObject private var player = AudioPlayerManager.shared
    @State private var lines: [LyricLine] = []
    @State private var isLoading = false
    @State private var suppressAutoScroll = false

    private var isSynced: Bool {
        lines.contains { $0.startSeconds != nil }
    }

    /// Index of the line with the latest timestamp that has still passed — the line currently "lit up".
    /// Scans the whole list rather than assuming lines arrive pre-sorted by Start, since a single
    /// out-of-order pair in the API response would otherwise throw off every line after it.
    /// Always nil for unsynced (plaintext) lyrics, since there's nothing to track.
    private var currentLineIndex: Int? {
        guard isSynced else { return nil }
        var bestIndex: Int?
        var bestStart: TimeInterval = -.infinity
        for (index, line) in lines.enumerated() {
            guard let start = line.startSeconds, start <= player.currentTime else { continue }
            if start >= bestStart {
                bestStart = start
                bestIndex = index
            }
        }
        return bestIndex
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if lines.isEmpty {
                    ContentUnavailableView("No Lyrics Available", systemImage: "quote.bubble")
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 20) {
                                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                    lineView(line, isCurrent: index == currentLineIndex)
                                        .id(index)
                                        .onTapGesture {
                                            guard let start = line.startSeconds else { return }
                                            suppressAutoScroll = true
                                            player.seek(to: start)
                                        }
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 40)
                        }
                        .onChange(of: currentLineIndex) { _, newValue in
                            guard let newValue else { return }
                            if suppressAutoScroll {
                                // This change came from a manual tap, not natural playback progression —
                                // the user is already looking at this line, so don't shift the list under
                                // their finger (which would make rapid re-taps land on a different row).
                                suppressAutoScroll = false
                                return
                            }
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
        .task(id: player.currentItem?.Id) {
            await loadLyrics()
        }
    }

    private func lineView(_ line: LyricLine, isCurrent: Bool) -> some View {
        Text(line.Text.isEmpty ? " " : line.Text)
            .font(isCurrent ? .title3.bold() : .title3)
            .foregroundStyle(!isSynced || isCurrent ? Color.primary : Color.secondary)
            .opacity(!isSynced || isCurrent ? 1 : 0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.25), value: isCurrent)
    }

    private func loadLyrics() async {
        guard let itemId = player.currentItem?.Id else {
            lines = []
            return
        }
        isLoading = true
        lines = (try? await JellyfinAPIClient.shared.fetchLyrics(itemId: itemId)) ?? []
        isLoading = false
    }
}
