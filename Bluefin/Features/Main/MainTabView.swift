//
//  MainTabView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import SwiftUI

struct MainTabView: View {
    @ObservedObject private var apiClient = JellyfinAPIClient.shared
    @ObservedObject private var player = AudioPlayerManager.shared
    @ObservedObject private var navigator = AppNavigator.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $navigator.selectedTab) {
                HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(AppTab.home)

                LibraryView()
                .tabItem {
                    Label("Library", systemImage: "music.note.list")
                }
                .tag(AppTab.library)

                SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(AppTab.search)

                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
            }

            if player.currentItem != nil {
                MiniPlayerView()
                    .padding(.horizontal, 16)
                    .padding(.bottom, MiniPlayerView.tabBarGap)
            }

            ToastOverlay()
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
