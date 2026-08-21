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
    @ObservedObject private var pinnedStore = PinnedPlaylistStore.shared

    init(title: String, itemType: LibraryItemKind, cacheKey: String) {
        self.title = title
        self.itemType = itemType
        _viewModel = StateObject(wrappedValue: LibraryListViewModel(cacheKey: cacheKey))
    }

    /// The pinned playlist first, if there is one — otherwise unchanged.
    private var displayedItems: [BaseItemDto] {
        guard itemType == .playlist,
              let pinnedId = pinnedStore.pinnedPlaylistId,
              let pinnedIndex = viewModel.items.firstIndex(where: { $0.Id == pinnedId }) else {
            return viewModel.items
        }
        var items = viewModel.items
        let pinned = items.remove(at: pinnedIndex)
        items.insert(pinned, at: 0)
        return items
    }

    var body: some View {
        Group {
            if !viewModel.hasSynced {
                NotSyncedView(itemsDescription: title.lowercased())
            } else if viewModel.items.isEmpty {
                ContentUnavailableView("No \(title)", systemImage: symbolForEmpty)
            } else {
                List(displayedItems) { item in
                    row(for: item)
                }
                .avoidsMiniPlayer()
            }
        }
        .navigationTitle(title)
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func row(for item: BaseItemDto) -> some View {
        let row = LibraryNavigableRow(item: item, isPinned: pinnedStore.isPinned(item.Id)) {
            let index = viewModel.items.firstIndex(of: item) ?? 0
            AudioPlayerManager.shared.play(queue: viewModel.items, startAt: index)
        }

        switch itemType {
        case .playlist:
            row.contextMenu {
                Button {
                    pinnedStore.togglePin(id: item.Id, name: item.Name)
                } label: {
                    if pinnedStore.isPinned(item.Id) {
                        Label("Unpin Playlist", systemImage: "pin.slash")
                    } else {
                        Label("Pin Playlist", systemImage: "pin")
                    }
                }
            }
        case .song:
            row.songActions(for: item)
        }
    }

    private var symbolForEmpty: String {
        switch itemType {
        case .song: return "music.note"
        case .playlist: return "music.note.list"
        }
    }
}
