//
//  TicketmasterBlacklistView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/23/26.
//

import SwiftUI

/// Artists hidden from Upcoming Concerts — blacklisted from a context menu on the Home screen's
/// concert card or from an artist's own concerts page; removed from the blacklist here.
struct TicketmasterBlacklistView: View {
    @ObservedObject private var store = TicketmasterBlacklistStore.shared

    var body: some View {
        Group {
            if store.blacklistedArtists.isEmpty {
                ContentUnavailableView(
                    "No Blacklisted Artists",
                    systemImage: "person.crop.circle.badge.xmark",
                    description: Text("Hide an artist from Upcoming Concerts and it'll show up here.")
                )
            } else {
                List {
                    ForEach(store.blacklistedArtists) { artist in
                        Text(artist.name)
                    }
                    .onDelete { offsets in
                        let idsToRemove = offsets.map { store.blacklistedArtists[$0].id }
                        idsToRemove.forEach(store.removeFromBlacklist)
                    }
                }
            }
        }
        .avoidsMiniPlayer()
        .navigationTitle("Blacklisted Artists")
        .navigationBarTitleDisplayMode(.inline)
    }
}
