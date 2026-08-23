//
//  TicketmasterRegionSettingsView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/23/26.
//

import SwiftUI

/// Restricts Upcoming Concerts to a single US state, Canadian province, or other country — picking
/// "All Regions" clears the restriction.
struct TicketmasterRegionSettingsView: View {
    @ObservedObject private var store = TicketmasterRegionStore.shared

    var body: some View {
        List {
            Section {
                regionRow(name: "All Regions", isSelected: store.selectedRegion == nil) {
                    store.select(nil)
                }
            }

            Section("United States") {
                ForEach(TicketmasterRegion.usStates) { region in
                    regionRow(name: region.name, isSelected: store.selectedRegion == region) {
                        store.select(region)
                    }
                }
            }

            Section("Canada") {
                ForEach(TicketmasterRegion.canadaProvinces) { region in
                    regionRow(name: region.name, isSelected: store.selectedRegion == region) {
                        store.select(region)
                    }
                }
            }

            Section("Other Countries") {
                ForEach(TicketmasterRegion.otherCountries) { region in
                    regionRow(name: region.name, isSelected: store.selectedRegion == region) {
                        store.select(region)
                    }
                }
            }
        }
        .avoidsMiniPlayer()
        .navigationTitle("Region")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func regionRow(name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(name)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}
