//
//  AppNavigator.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/21/26.
//

import Combine
import SwiftUI

enum AppTab: Hashable {
    case home, library, search, settings
}

/// Lets a modally-presented screen (like the large player) navigate somewhere in the main tab
/// UI behind it — pushing onto whichever tab the user is currently on, rather than always forcing
/// a specific tab or pushing within its own presentation. The caller is still responsible for
/// dismissing itself.
@MainActor
final class AppNavigator: ObservableObject {
    static let shared = AppNavigator()

    @Published var selectedTab: AppTab = .home
    @Published var homePath = NavigationPath()
    @Published var libraryPath = NavigationPath()
    @Published var searchPath = NavigationPath()

    private init() {}

    /// Pushes onto the current tab's own path. Settings has no `LibraryRoute` destination of its
    /// own to push onto, so navigating from there is expected to land you on Library instead.
    func navigate(to route: LibraryRoute) {
        switch selectedTab {
        case .home:
            homePath.append(route)
        case .library:
            libraryPath.append(route)
        case .search:
            searchPath.append(route)
        case .settings:
            selectedTab = .library
            libraryPath.append(route)
        }
    }
}
