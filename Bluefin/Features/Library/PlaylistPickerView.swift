//
//  PlaylistPickerView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import SwiftUI

/// Sheet for picking which playlist to add a song to. Reads from `LibraryCache` only — same as
/// every other browsing screen, populated by an explicit library sync rather than a live fetch.
/// Dismisses immediately on selection; the actual add happens in the background via
/// `PlaylistActionService`, which reports the result through a toast once the server confirms it.
struct PlaylistPickerView: View {
    let song: BaseItemDto
    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [BaseItemDto]?

    var body: some View {
        NavigationStack {
            Group {
                if let playlists, playlists.isEmpty {
                    ContentUnavailableView("No Playlists", systemImage: "music.note.list")
                } else if let playlists {
                    List(playlists) { playlist in
                        Button {
                            dismiss()
                            PlaylistActionService.addSong(song, toPlaylistId: playlist.Id, playlistName: playlist.Name)
                        } label: {
                            HStack(spacing: 12) {
                                CachedAsyncImage(itemId: playlist.Id) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.secondary.opacity(0.15))
                                        .overlay(Image(systemName: "music.note.list").foregroundStyle(.secondary))
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                Text(playlist.Name)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                } else {
                    NotSyncedView(itemsDescription: "playlists")
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            playlists = await LibraryCache.shared.items(for: "playlists")
        }
    }
}
