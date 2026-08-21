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
        .modelContainer(Persistence.shared)
    }
}

