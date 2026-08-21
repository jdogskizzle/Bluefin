//
//  SearchView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel(apiClient: .shared)
    @ObservedObject private var apiClient = JellyfinAPIClient.shared

    var body: some View {
        NavigationStack {
            Group {
                if apiClient.selectedLibraryId == nil {
                    ContentUnavailableView(
                        "No Music Library Selected",
                        systemImage: "music.note.list",
                        description: Text("Choose a music library in Settings to start searching.")
                    )
                } else if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView.search
                } else if viewModel.isLoading {
                    ProgressView()
                } else if let error = viewModel.errorMessage {
                    ContentUnavailableView(
                        "Couldn't Search",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if !viewModel.hasResults {
                    ContentUnavailableView.search(text: viewModel.query)
                } else {
                    List {
                        if !viewModel.artists.isEmpty {
                            Section("Artists") {
                                ForEach(viewModel.artists) { item in
                                    LibraryNavigableRow(item: item)
                                }
                            }
                        }
                        if !viewModel.albums.isEmpty {
                            Section("Albums") {
                                ForEach(viewModel.albums) { item in
                                    LibraryNavigableRow(item: item)
                                }
                            }
                        }
                        if !viewModel.songs.isEmpty {
                            Section("Songs") {
                                ForEach(viewModel.songs) { item in
                                    LibraryNavigableRow(item: item) {
                                        let index = viewModel.songs.firstIndex(of: item) ?? 0
                                        AudioPlayerManager.shared.play(queue: viewModel.songs, startAt: index)
                                    }
                                    .songActions(for: item)
                                }
                            }
                        }
                    }
                    .avoidsMiniPlayer()
                }
            }
            .navigationTitle("Search")
            .searchable(text: $viewModel.query, prompt: "Artists, albums, songs")
            .navigationDestination(for: LibraryRoute.self) { route in
                LibraryDestinationView(route: route)
            }
            .task(id: viewModel.query) {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await viewModel.search()
            }
        }
    }
}

struct SearchView_Previews: PreviewProvider {
    static var previews: some View {
        SearchView()
    }
}
