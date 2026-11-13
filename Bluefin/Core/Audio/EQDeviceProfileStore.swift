//
//  EQDeviceProfileStore.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 11/13/26.
//

import AVFoundation
import Combine
import Foundation

/// A remembered audio output (a specific Bluetooth device, CarPlay, the phone's own speaker, …) with
/// an EQ preset the app should switch to whenever that output becomes active. Keyed by the output
/// port's own `uid`, which iOS keeps stable per physical device (e.g. the same paired headphones)
/// rather than per connection.
struct EQDeviceProfile: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var portType: String
    /// `nil` means "Default" — flat/no EQ coloration — rather than "not yet configured": every
    /// discovered device starts here until the user explicitly assigns a preset to it.
    var presetId: UUID?

    var icon: String {
        #if canImport(UIKit)
        switch portType {
        case AVAudioSession.Port.carAudio.rawValue:
            return "car.fill"
        case AVAudioSession.Port.headphones.rawValue:
            return "headphones"
        case AVAudioSession.Port.bluetoothA2DP.rawValue, AVAudioSession.Port.bluetoothHFP.rawValue,
            AVAudioSession.Port.bluetoothLE.rawValue:
            return "wave.3.right"
        case AVAudioSession.Port.builtInSpeaker.rawValue:
            return "speaker.wave.2.fill"
        case AVAudioSession.Port.builtInReceiver.rawValue:
            return "phone.fill"
        case AVAudioSession.Port.airPlay.rawValue:
            return "airplayaudio"
        case AVAudioSession.Port.usbAudio.rawValue, AVAudioSession.Port.lineOut.rawValue:
            return "cable.connector"
        default:
            return "hifispeaker.fill"
        }
        #else
        return "hifispeaker.fill"
        #endif
    }
}

/// Watches which audio output is active and switches `EqualizerSettings` to match, per the user's
/// own per-device assignments below — e.g. the car's Bluetooth gets "Default" (flat), a pair of
/// headphones gets a "Bass Boost" preset. A device is only ever auto-applied once it's actually been
/// seen (`applyProfileForCurrentRoute`, driven by `AVAudioSession.routeChangeNotification`), which is
/// also what populates `devices` for `EQDeviceProfilesView` to list and let the user rename/assign.
@MainActor
final class EQDeviceProfileStore: ObservableObject {
    static let shared = EQDeviceProfileStore()

    @Published private(set) var devices: [EQDeviceProfile] = []

    private static let defaultsKey = "com.bluefin.eq.deviceProfiles"
    private var routeChangeObserver: NSObjectProtocol?
    /// Avoids re-applying the same device's profile (and re-triggering `activePresetId`/gain
    /// `@Published` updates) on every route-change notification — some fire for reasons other than
    /// the active output actually changing (e.g. a category/mode change) and would otherwise cause
    /// the Equalizer screen to visibly reset mid-interaction for no reason.
    private var lastAppliedDeviceId: String?

    private init() {
        load()
        #if canImport(UIKit)
        observeRouteChanges()
        applyProfileForCurrentRoute()
        #endif
    }

    /// No-op beyond triggering the lazy `shared` singleton's `init()` — called at app launch
    /// (`BluefinApp`'s `AppDelegate`) so route-change observation starts immediately rather than
    /// waiting for the user to first open the Equalizer or its device-list settings screen.
    func activate() {}

    func rename(_ device: EQDeviceProfile, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index].name = trimmed
        persist()
    }

    /// `presetId` of `nil` assigns "Default" (flat). Re-applies immediately if `device` is the
    /// currently active output, so picking a new preset takes effect right away rather than waiting
    /// for the next route change.
    func assignPreset(_ presetId: UUID?, to device: EQDeviceProfile) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index].presetId = presetId
        persist()
        if device.id == lastAppliedDeviceId {
            apply(devices[index])
        }
    }

    func remove(_ device: EQDeviceProfile) {
        devices.removeAll { $0.id == device.id }
        persist()
    }

    @discardableResult
    private func registerIfNeeded(uid: String, defaultName: String, portType: String) -> EQDeviceProfile {
        if let existing = devices.first(where: { $0.id == uid }) { return existing }
        let device = EQDeviceProfile(id: uid, name: defaultName, portType: portType, presetId: nil)
        devices.append(device)
        persist()
        return device
    }

    private func apply(_ device: EQDeviceProfile) {
        let settings = EqualizerSettings.shared
        guard let presetId = device.presetId,
            let preset = settings.presets.first(where: { $0.id == presetId })
        else {
            settings.resetToDefault()
            return
        }
        settings.isEnabled = true
        settings.loadPreset(preset)
    }

    #if canImport(UIKit)
    private func observeRouteChanges() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyProfileForCurrentRoute()
            }
        }
    }

    func applyProfileForCurrentRoute() {
        guard let output = AVAudioSession.sharedInstance().currentRoute.outputs.first,
            output.uid != lastAppliedDeviceId
        else { return }
        lastAppliedDeviceId = output.uid
        let device = registerIfNeeded(
            uid: output.uid, defaultName: output.portName, portType: output.portType.rawValue)
        apply(device)
    }
    #endif

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
            let decoded = try? JSONDecoder().decode([EQDeviceProfile].self, from: data)
        else { return }
        devices = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
