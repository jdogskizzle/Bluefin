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

/// The actions for a song, shared between the long-press context menu on song rows, their swipe
/// actions, and the large player's "..." menu — so they stay in sync by construction rather than
/// by keeping copies in step. `removableFrom` is only passed by call sites that know the song is
/// being viewed within that playlist; `isAlbumContext` by call sites showing it as part of its own
/// album (`AlbumDetailView`), where "Go to Album" would just point at the screen already showing.
/// `showsGoToLinks` is `false` only for `NowPlayingView`, which already has its own "Go to Artist"/
/// "Go to Album" elsewhere on that screen — showing them here too would just be a duplicate.
struct SongPlaylistMenuItems: View {
    let song: BaseItemDto
    @Binding var showPicker: Bool
    @Binding var showDetails: Bool
    var removableFrom: RemovableFromPlaylist? = nil
    var isAlbumContext: Bool = false
    var showsGoToLinks: Bool = true
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
        if showsGoToLinks {
            Button {
                Task { await goToArtist() }
            } label: {
                Label("Go to Artist", systemImage: "music.mic")
            }
            if !isAlbumContext {
                Button {
                    Task { await goToAlbum() }
                } label: {
                    Label("Go to Album", systemImage: "square.stack")
                }
            }
        }
        if let removableFrom {
            Button(role: .destructive) {
                PlaylistActionService.removeSong(song, fromPlaylistId: removableFrom.playlistId, playlistName: removableFrom.playlistName)
            } label: {
                Label("Remove from Playlist", systemImage: "minus.circle")
            }
        }
        Button {
            showDetails = true
        } label: {
            Label("Details", systemImage: "info.circle")
        }
    }

    private func goToArtist() async {
        guard let artistName = song.AlbumArtist ?? song.Artists?.first,
              let libraryId = JellyfinAPIClient.shared.selectedLibraryId,
              let artists = await LibraryCache.shared.items(for: "artists:\(libraryId)"),
              let artist = artists.first(where: { $0.Name == artistName }) else {
            ToastCenter.shared.show("Couldn't find that artist", isError: true)
            return
        }
        AppNavigator.shared.navigate(to: .artistAlbums(artist))
    }

    private func goToAlbum() async {
        guard let albumId = song.AlbumId,
              let libraryId = JellyfinAPIClient.shared.selectedLibraryId,
              let albums = await LibraryCache.shared.items(for: "albums:\(libraryId)"),
              let album = albums.first(where: { $0.Id == albumId }) else {
            ToastCenter.shared.show("Couldn't find that album", isError: true)
            return
        }
        AppNavigator.shared.navigate(to: .albumSongs(album))
    }
}

/// Long-press context menu + swipe actions for a song row inside a `List`: leading (left-to-right)
/// swipe offers "Add to Queue"; trailing (right-to-left) offers the playlist "add" actions.
/// "Remove from Playlist" and "Go to Artist"/"Go to Album" are context-menu only, not swipe actions.
private struct SongActionsModifier: ViewModifier {
    let song: BaseItemDto
    var removableFrom: RemovableFromPlaylist? = nil
    var isAlbumContext: Bool = false
    @State private var showPicker = false
    @State private var showDetails = false
    @ObservedObject private var pinnedStore = PinnedPlaylistStore.shared

    func body(content: Content) -> some View {
        content
            .contextMenu {
                SongPlaylistMenuItems(song: song, showPicker: $showPicker, showDetails: $showDetails, removableFrom: removableFrom, isAlbumContext: isAlbumContext)
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
            .sheet(isPresented: $showDetails) {
                SongDetailsView(song: song)
            }
    }
}

extension View {
    /// Long-press context menu + swipe actions for a song. Pass `removableFrom` when `song` is
    /// being shown as part of that specific playlist, to also offer "Remove from Playlist" in the
    /// context menu; pass `isAlbumContext: true` when it's being shown as part of its own album
    /// (`AlbumDetailView`), to omit the otherwise-redundant "Go to Album".
    func songActions(for song: BaseItemDto, removableFrom: RemovableFromPlaylist? = nil, isAlbumContext: Bool = false) -> some View {
        modifier(SongActionsModifier(song: song, removableFrom: removableFrom, isAlbumContext: isAlbumContext))
    }
}
