//
//  StreamingQualitySettings.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/22/26.
//

import Combine
import Foundation

enum StreamingQuality: String, CaseIterable, Identifiable {
    case original
    case kbps320
    case kbps256
    case kbps128

    var id: String { rawValue }

    /// `nil` means the original file, untranscoded.
    var bitRateKbps: Int? {
        switch self {
        case .original: return nil
        case .kbps320: return 320
        case .kbps256: return 256
        case .kbps128: return 128
        }
    }

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .kbps320: return "320 kbps"
        case .kbps256: return "256 kbps"
        case .kbps128: return "128 kbps"
        }
    }
}

/// Independent quality caps for Wi-Fi streaming, cellular streaming, and downloads — persisted
/// separately so, for example, cellular can default to a lower bitrate to save data while
/// downloads (typically deliberate, one-time transfers) default to the original file.
@MainActor
final class StreamingQualitySettings: ObservableObject {
    static let shared = StreamingQualitySettings()

    @Published var wifiQuality: StreamingQuality {
        didSet { UserDefaults.standard.set(wifiQuality.rawValue, forKey: Self.wifiKey) }
    }
    @Published var cellularQuality: StreamingQuality {
        didSet { UserDefaults.standard.set(cellularQuality.rawValue, forKey: Self.cellularKey) }
    }
    @Published var downloadQuality: StreamingQuality {
        didSet { UserDefaults.standard.set(downloadQuality.rawValue, forKey: Self.downloadKey) }
    }

    private static let wifiKey = "com.bluefin.quality.wifi"
    private static let cellularKey = "com.bluefin.quality.cellular"
    private static let downloadKey = "com.bluefin.quality.download"

    private init() {
        wifiQuality = Self.load(key: Self.wifiKey, default: .original)
        cellularQuality = Self.load(key: Self.cellularKey, default: .kbps256)
        downloadQuality = Self.load(key: Self.downloadKey, default: .original)
    }

    private static func load(key: String, default defaultValue: StreamingQuality) -> StreamingQuality {
        guard let raw = UserDefaults.standard.string(forKey: key), let value = StreamingQuality(rawValue: raw) else {
            return defaultValue
        }
        return value
    }

    /// The bitrate cap to request right now for live streaming/pre-caching, based on the current
    /// connection — `nil` means original/unlimited quality.
    func currentStreamingBitrateKbps() -> Int? {
        let quality = NetworkMonitor.shared.isOnCellular ? cellularQuality : wifiQuality
        return quality.bitRateKbps
    }
}
