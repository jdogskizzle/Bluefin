//
//  SongPlaylistMenuItems.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import SwiftUI

/// Identifies the playlist a song row is being shown inside of, so its context menu can offer
/// "Remove from Playlist" — only meaningful when the song is being browsed as part of that specific
/// playlist (`PlaylistDetailView`), not in a general list like Songs or Search.
struct RemovableFromPlaylist {
    let playlistId: String
    let playlistName: String
}

/// The playlist actions for a song, shared between the long-press context menu on song rows, their
/// swipe actions, and the large player's "..." menu — so they stay in sync by construction rather
/// than by keeping copies in step. `removableFrom` is only passed by call sites that know the song
/// is being viewed within that playlist.
struct SongPlaylistMenuItems: View {
    let song: BaseItemDto
    @Binding var showPicker: Bool
    var removableFrom: RemovableFromPlaylist? = nil
    @ObservedObject private var pinnedStore = PinnedPlaylistStore.shared

    var body: some View {
        if let pinnedId = pinnedStore.pinnedPlaylistId, let pinnedName = pinnedStore.pinnedPlaylistName {
            Button {
                PlaylistActionService.addSong(song, toPlaylistId: pinnedId, playlistName: pinnedName)
            } label: {
                Label("Add to \(pinnedName)", systemImage: "pin")
            }
        }
        Button {
            showPicker = true
        } label: {
            Label("Add to Playlist", systemImage: "text.badge.plus")
        }
        Button {
            AudioPlayerManager.shared.addToSubqueue(song)
        } label: {
            Label("Add to Queue", systemImage: "text.insert")
        }
        if let removableFrom {
            Button(role: .destructive) {
                PlaylistActionService.removeSong(song, fromPlaylistId: removableFrom.playlistId, playlistName: removableFrom.playlistName)
            } label: {
                Label("Remove from Playlist", systemImage: "minus.circle")
            }
        }
    }
}

/// Long-press context menu + swipe actions for a song row inside a `List`: leading (left-to-right)
/// swipe offers "Add to Queue"; trailing (right-to-left) offers the playlist "add" actions.
/// "Remove from Playlist" is context-menu only, not a swipe action.
private struct SongActionsModifier: ViewModifier {
    let song: BaseItemDto
    var removableFrom: RemovableFromPlaylist? = nil
    @State private var showPicker = false
    @ObservedObject private var pinnedStore = PinnedPlaylistStore.shared

    func body(content: Content) -> some View {
        content
            .contextMenu {
                SongPlaylistMenuItems(song: song, showPicker: $showPicker, removableFrom: removableFrom)
            }
            .swipeActions(edge: .leading) {
                Button {
                    AudioPlayerManager.shared.addToSubqueue(song)
                } label: {
                    Image(systemName: "text.insert")
                }
                .tint(.orange)
            }
            .swipeActions(edge: .trailing) {
                if let pinnedId = pinnedStore.pinnedPlaylistId, let pinnedName = pinnedStore.pinnedPlaylistName {
                    Button {
                        PlaylistActionService.addSong(song, toPlaylistId: pinnedId, playlistName: pinnedName)
                    } label: {
                        Image(systemName: "pin")
                    }
                    .tint(.blue)
                }
                Button {
                    showPicker = true
                } label: {
                    Image(systemName: "text.badge.plus")
                }
                .tint(.indigo)
            }
            .sheet(isPresented: $showPicker) {
                PlaylistPickerView(song: song)
            }
    }
}

extension View {
    /// Long-press context menu + swipe actions for adding `song` to the play queue or a playlist.
    /// Pass `removableFrom` when `song` is being shown as part of that specific playlist, to also
    /// offer "Remove from Playlist" in the context menu.
    func songActions(for song: BaseItemDto, removableFrom: RemovableFromPlaylist? = nil) -> some View {
        modifier(SongActionsModifier(song: song, removableFrom: removableFrom))
    }
}
