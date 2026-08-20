//
//  SearchViewModel.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var artists: [BaseItemDto] = []
    @Published var albums: [BaseItemDto] = []
    @Published var songs: [BaseItemDto] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiClient: JellyfinAPIClient

    init(apiClient: JellyfinAPIClient) {
        self.apiClient = apiClient
    }

    var hasResults: Bool {
        !artists.isEmpty || !albums.isEmpty || !songs.isEmpty
    }

    func search() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            artists = []
            albums = []
            songs = []
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            async let artistsResult = apiClient.fetchItems(
                parentId: apiClient.selectedLibraryId,
                includeItemTypes: "MusicArtist",
                searchTerm: term
            )
            async let albumsResult = apiClient.fetchItems(
                parentId: apiClient.selectedLibraryId,
                includeItemTypes: "MusicAlbum",
                searchTerm: term
            )
            async let songsResult = apiClient.fetchItems(
                parentId: apiClient.selectedLibraryId,
                includeItemTypes: "Audio",
                searchTerm: term
            )

            let (fetchedArtists, fetchedAlbums, fetchedSongs) = try await (artistsResult, albumsResult, songsResult)
            artists = fetchedArtists
            albums = fetchedAlbums
            songs = fetchedSongs
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
