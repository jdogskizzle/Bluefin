//
//  NotSyncedView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import SwiftUI

/// Shown in place of a library list screen's empty state when nothing has been cached for it yet —
/// distinct from "the library really has zero of these," which is what an empty (but synced)
/// result means. Points the user at the explicit sync action in Settings, since that's the only
/// thing that ever populates these screens.
struct NotSyncedView: View {
    let itemsDescription: String

    var body: some View {
        ContentUnavailableView(
            "Not Synced Yet",
            systemImage: "arrow.triangle.2.circlepath",
            description: Text("Sync your library in Settings to see your \(itemsDescription).")
        )
    }
}
