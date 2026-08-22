//
//  LibraryView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import SwiftUI

struct LibraryView: View {
    @ObservedObject private var apiClient = JellyfinAPIClient.shared
    @ObservedObject private var navigator = AppNavigator.shared

    var body: some View {
        NavigationStack(path: $navigator.libraryPath) {
            Group {
                if apiClient.selectedLibraryId == nil {
                    ContentUnavailableView(
                        "No Music Library Selected",
                        systemImage: "music.note.list",
                        description: Text("Choose a music library in Settings to start browsing.")
                    )
                } else {
                    List {
                        NavigationLink(value: LibraryRoute.artists) {
                            Label("Artists", systemImage: "music.mic")
                        }
                        NavigationLink(value: LibraryRoute.albums) {
                            Label("Albums", systemImage: "square.stack")
                        }
                        NavigationLink(value: LibraryRoute.songs) {
                            Label("Songs", systemImage: "music.note")
                        }
                        NavigationLink(value: LibraryRoute.playlists) {
                            Label("Playlists", systemImage: "music.note.list")
                        }
                        NavigationLink(value: LibraryRoute.downloads) {
                            Label("Downloads", systemImage: "arrow.down.circle")
                        }
                        NavigationLink(value: LibraryRoute.favorites) {
                            Label("Favorites", systemImage: "heart")
                        }
                        NavigationLink(value: LibraryRoute.genres) {
                            Label("Genres", systemImage: "guitars")
                        }
                    }
                }
            }
            .avoidsMiniPlayer()
            .navigationTitle("Library")
            .navigationDestination(for: LibraryRoute.self) { route in
                LibraryDestinationView(route: route)
            }
            .navigationDestination(for: LidarrCalendarItem.self) { release in
                LidarrAlbumDetailView(release: release)
            }
        }
    }
}

struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
    }
}
