//
//  BluefinApp.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import SwiftUI
import SwiftData

/// Reconnects to the background download session at launch, and hands iOS's background-session
/// completion handler to it — required so a download that finished while the app was suspended or
/// terminated actually gets acknowledged and the delegate callbacks for it get delivered.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundDownloadSession.shared.activate()
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundDownloadSession.shared.activate()
        BackgroundDownloadSession.shared.backgroundCompletionHandler = completionHandler
    }
}

@main
struct BluefinApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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

