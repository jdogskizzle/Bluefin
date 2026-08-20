//
//  BluefinApp.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import SwiftUI
import SwiftData

@main
struct BluefinApp: App {
    @StateObject private var apiClient = JellyfinAPIClient.shared
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if apiClient.isAuthorized {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(apiClient)
            .animation(.default, value: apiClient.isAuthorized)
        }
        .modelContainer(sharedModelContainer)
    }
}

