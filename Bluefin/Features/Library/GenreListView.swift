//
//  GenreListView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/22/26.
//

import SwiftUI

struct GenreListView: View {
    @StateObject private var viewModel: LibraryListViewModel

    init(cacheKey: String) {
        _viewModel = StateObject(wrappedValue: LibraryListViewModel(cacheKey: cacheKey))
    }

    private var sortedGenres: [BaseItemDto] {
        viewModel.items.sorted { $0.Name.localizedCaseInsensitiveCompare($1.Name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if !viewModel.hasSynced {
                NotSyncedView(itemsDescription: "genres")
            } else if viewModel.items.isEmpty {
                ContentUnavailableView("No Genres", systemImage: "guitars")
            } else {
                List(sortedGenres) { genre in
                    LibraryNavigableRow(item: genre)
                }
                .avoidsMiniPlayer()
            }
        }
        .navigationTitle("Genres")
        .task {
            await viewModel.load()
        }
    }
}
