//
//  TicketmasterRegionStore.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/23/26.
//

import Combine
import Foundation

/// The single region (US state, Canadian province, or country) Upcoming Concerts is currently
/// restricted to — `nil` means no restriction, every region shown.
@MainActor
final class TicketmasterRegionStore: ObservableObject {
    static let shared = TicketmasterRegionStore()

    @Published private(set) var selectedRegion: TicketmasterRegion?

    private static let defaultsKey = "com.bluefin.ticketmaster.selectedRegion"

    private init() {
        load()
    }

    func select(_ region: TicketmasterRegion?) {
        selectedRegion = region
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode(TicketmasterRegion.self, from: data) else {
            return
        }
        selectedRegion = decoded
    }

    private func save() {
        guard let selectedRegion else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            return
        }
        guard let data = try? JSONEncoder().encode(selectedRegion) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
