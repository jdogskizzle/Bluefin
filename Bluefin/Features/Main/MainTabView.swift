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
    
    var body: some View {
        TabView {
            NavigationStack {
                Text("Welcome to Bluefin")
                    .navigationTitle("Home")
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }

            LibraryView()
            .tabItem {
                Label("Library", systemImage: "music.note.list")
            }

            SearchView()
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
