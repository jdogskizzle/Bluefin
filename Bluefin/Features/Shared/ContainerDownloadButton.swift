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
/// `group` identifies the container itself, so the Library "Downloads" section can show just it
/// rather than every song inside it individually — see `DownloadGroupInfo`.
struct ContainerDownloadButton: View {
    let songs: [BaseItemDto]
    let group: DownloadGroupInfo
    /// Set by the "Remove Download" case instead of removing directly — presenting a confirmation
    /// from inside a `Menu`'s content isn't reliable, so the actual `.confirmRemoveDownload(...)`
    /// is attached by the caller, outside the menu (matching how `SongPlaylistMenuItems` hoists its
    /// own sheet-presenting state the same way).
    @Binding var showRemoveConfirmation: Bool
    @ObservedObject private var downloadManager = DownloadManager.shared

    var body: some View {
        switch downloadManager.state(for: songs) {
        case .notDownloaded:
            Button {
                downloadManager.download(songs, group: group)
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
                showRemoveConfirmation = true
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        }
    }
}

extension View {
    /// Confirmation before actually deleting downloaded audio — shared by the per-song
    /// (`SongPlaylistMenuItems`) and per-container (`ContainerDownloadButton`) "Remove Download"
    /// actions, so both read the same either way regardless of how many songs are involved.
    func confirmRemoveDownload(songs: [BaseItemDto], group: DownloadGroupInfo? = nil, isPresented: Binding<Bool>) -> some View {
        confirmationDialog(
            songs.count == 1 ? "Remove Download?" : "Remove \(songs.count) Downloads?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                DownloadManager.shared.removeDownload(songs, group: group)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
