//
//  LibraryListView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import SwiftUI

struct LibraryListView: View {
    let title: String
    let itemType: LibraryItemKind
    @StateObject private var viewModel: LibraryListViewModel

    init(title: String, itemType: LibraryItemKind, fetch: @escaping () async throws -> [BaseItemDto]) {
        self.title = title
        self.itemType = itemType
        _viewModel = StateObject(wrappedValue: LibraryListViewModel(fetch: fetch))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView(
                    "Couldn't Load \(title)",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if viewModel.items.isEmpty {
                ContentUnavailableView("No \(title)", systemImage: symbolForEmpty)
            } else {
                List(viewModel.items) { item in
                    rowOrLink(for: item)
                }
            }
        }
        .navigationTitle(title)
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func rowOrLink(for item: BaseItemDto) -> some View {
        if let route = route(for: item) {
            NavigationLink(value: route) {
                LibraryItemRow(item: item)
            }
        } else {
            LibraryItemRow(item: item)
        }
    }

    private func route(for item: BaseItemDto) -> LibraryRoute? {
        switch item.ItemType {
        case "MusicArtist": return .artistAlbums(item)
        case "MusicAlbum": return .albumSongs(item)
        case "Playlist": return .playlistSongs(item)
        default: return nil
        }
    }

    private var symbolForEmpty: String {
        switch itemType {
        case .artist: return "music.mic"
        case .album: return "square.stack"
        case .song: return "music.note"
        case .playlist: return "music.note.list"
        }
    }
}
