//
//  LibraryListViewModel.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import Foundation

enum LibraryItemKind {
    case song, playlist
}

@MainActor
final class LibraryListViewModel: ObservableObject {
    @Published var items: [BaseItemDto] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let fetch: () async throws -> [BaseItemDto]

    init(fetch: @escaping () async throws -> [BaseItemDto]) {
        self.fetch = fetch
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await fetch()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
