//
//  EqualizerSettings.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/21/26.
//

import Combine
import Foundation

nonisolated enum EqualizerBands {
    static let frequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let count = frequencies.count
    static let gainRange: ClosedRange<Double> = -12...12
    static let flatGains: [Double] = Array(repeating: 0, count: count)
}

struct EqualizerPreset: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var gains: [Double]

    init(id: UUID = UUID(), name: String, gains: [Double]) {
        self.id = id
        self.name = name
        self.gains = gains
    }
}

@MainActor
final class EqualizerSettings: ObservableObject {
    static let shared = EqualizerSettings()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledDefaultsKey)
            pushToEngine()
        }
    }

    @Published var gains: [Double] {
        didSet {
            UserDefaults.standard.set(gains, forKey: Self.gainsDefaultsKey)
            pushToEngine()
        }
    }

    @Published private(set) var presets: [EqualizerPreset] {
        didSet {
            guard let data = try? JSONEncoder().encode(presets) else { return }
            UserDefaults.standard.set(data, forKey: Self.presetsDefaultsKey)
        }
    }

    @Published var activePresetId: UUID?

    private static let enabledDefaultsKey = "com.bluefin.eq.enabled"
    private static let gainsDefaultsKey = "com.bluefin.eq.gains"
    private static let presetsDefaultsKey = "com.bluefin.eq.presets"

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        gains = UserDefaults.standard.array(forKey: Self.gainsDefaultsKey) as? [Double] ?? EqualizerBands.flatGains
        if let data = UserDefaults.standard.data(forKey: Self.presetsDefaultsKey),
           let stored = try? JSONDecoder().decode([EqualizerPreset].self, from: data) {
            presets = stored
        } else {
            presets = []
        }
        pushToEngine()
    }

    private func pushToEngine() {
        EqualizerEngine.shared.updateSettings(isEnabled: isEnabled, gains: gains)
    }

    func savePreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = presets.firstIndex(where: { $0.name == trimmed }) {
            presets[index].gains = gains
            activePresetId = presets[index].id
        } else {
            let preset = EqualizerPreset(name: trimmed, gains: gains)
            presets.append(preset)
            activePresetId = preset.id
        }
    }

    func loadPreset(_ preset: EqualizerPreset) {
        gains = preset.gains
        activePresetId = preset.id
    }

    func deletePreset(_ preset: EqualizerPreset) {
        presets.removeAll { $0.id == preset.id }
        if activePresetId == preset.id {
            activePresetId = nil
        }
    }

    func resetToDefault() {
        gains = EqualizerBands.flatGains
        activePresetId = nil
    }
}
