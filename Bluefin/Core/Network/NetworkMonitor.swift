//
//  NetworkMonitor.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/22/26.
//

import Combine
import Network

/// Tracks whether the device is currently on a cellular connection (vs. Wi-Fi) — the only signal
/// `StreamingQualitySettings` needs to pick between its Wi-Fi and cellular streaming quality.
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnCellular = false

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            // A path can report both interfaces as available (e.g. Wi-Fi with cellular as a
            // fallback) — Wi-Fi being present at all means that's the one actually in use.
            let isCellular = path.status == .satisfied && path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi)
            Task { @MainActor in
                NetworkMonitor.shared.isOnCellular = isCellular
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.bluefin.networkMonitor"))
    }
}
