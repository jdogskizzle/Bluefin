//
//  ContainerDownloadButton.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/22/26.
//

import SwiftUI

/// Download/Cancel Download/Remove Download for a whole album, artist, or playlist's worth of
/// songs at once — the container-level counterpart to the per-song button in
/// `SongPlaylistMenuItems`, sharing the same three-state logic via `DownloadManager.state(for:)`.
struct ContainerDownloadButton: View {
    let songs: [BaseItemDto]
    @ObservedObject private var downloadManager = DownloadManager.shared

    var body: some View {
        switch downloadManager.state(for: songs) {
        case .notDownloaded:
            Button {
                downloadManager.download(songs)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        case .downloading:
            Button(role: .destructive) {
                downloadManager.cancelDownload(songs)
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
        case .downloaded:
            Button(role: .destructive) {
                downloadManager.removeDownload(songs)
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        }
    }
}
