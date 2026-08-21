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

    init(title: String, itemType: LibraryItemKind, cacheKey: String) {
        self.title = title
        self.itemType = itemType
        _viewModel = StateObject(wrappedValue: LibraryListViewModel(cacheKey: cacheKey))
    }

    var body: some View {
        Group {
            if !viewModel.hasSynced {
                NotSyncedView(itemsDescription: title.lowercased())
            } else if viewModel.items.isEmpty {
                ContentUnavailableView("No \(title)", systemImage: symbolForEmpty)
            } else {
                List(viewModel.items) { item in
                    LibraryNavigableRow(item: item) {
                        let index = viewModel.items.firstIndex(of: item) ?? 0
                        AudioPlayerManager.shared.play(queue: viewModel.items, startAt: index)
                    }
                }
            }
        }
        .navigationTitle(title)
        .task {
            await viewModel.load()
        }
    }

    private var symbolForEmpty: String {
        switch itemType {
        case .song: return "music.note"
        case .playlist: return "music.note.list"
        }
    }
}
