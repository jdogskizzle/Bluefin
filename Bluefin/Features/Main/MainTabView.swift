//
//  MainTabView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import SwiftUI

struct MainTabView: View {
    @ObservedObject private var apiClient = JellyfinAPIClient.shared
    
    var body: some View {
        TabView {
            NavigationView {
                VStack(spacing: 16) {
                    Text("Welcome to Bluefin")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    if let url = apiClient.serverURL {
                        Text("Connected to:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(url.absoluteString)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: {
                        apiClient.logout()
                    }) {
                        Text("Sign Out")
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 20)
                }
                .navigationTitle("Home")
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            
            NavigationView {
                Text("Library content will appear here")
                    .navigationTitle("Library")
            }
            .tabItem {
                Label("Library", systemImage: "music.note.list")
            }
            
            NavigationView {
                Text("Search your library")
                    .navigationTitle("Search")
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            
            NavigationView {
                Text("App Settings")
                    .navigationTitle("Settings")
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
