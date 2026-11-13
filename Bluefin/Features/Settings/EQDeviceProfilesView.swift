//
//  EQDeviceProfilesView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 11/13/26.
//

import SwiftUI

/// Lets the user rename each audio output Bluefin has seen (a specific Bluetooth device, CarPlay,
/// the phone's own speaker, …) and assign it an Equalizer preset, auto-applied whenever that output
/// becomes active again — see `EQDeviceProfileStore`.
struct EQDeviceProfilesView: View {
    @ObservedObject private var deviceStore = EQDeviceProfileStore.shared
    @ObservedObject private var eqSettings = EqualizerSettings.shared
    @State private var renamingDevice: EQDeviceProfile?
    @State private var renameText = ""

    var body: some View {
        Group {
            if deviceStore.devices.isEmpty {
                ContentUnavailableView(
                    "No Devices Yet",
                    systemImage: "hifispeaker",
                    description: Text("Connect headphones, a car, or another audio output once and it'll show up here to assign an EQ preset to.")
                )
            } else {
                List {
                    Section {
                        ForEach(deviceStore.devices) { device in
                            deviceRow(device)
                        }
                    } footer: {
                        Text("Every device starts on \"Default\" (flat, no coloration) until you assign it a preset.")
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Auto EQ by Device")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename Device", isPresented: Binding(
            get: { renamingDevice != nil },
            set: { if !$0 { renamingDevice = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let renamingDevice {
                    deviceStore.rename(renamingDevice, to: renameText)
                }
            }
        }
    }

    private func deviceRow(_ device: EQDeviceProfile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: device.icon)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            Text(device.name)

            Spacer()

            Menu {
                Button {
                    deviceStore.assignPreset(nil, to: device)
                } label: {
                    assignmentLabel("Default (Flat)", isSelected: device.presetId == nil)
                }
                ForEach(eqSettings.presets) { preset in
                    Button {
                        deviceStore.assignPreset(preset.id, to: device)
                    } label: {
                        assignmentLabel(preset.name, isSelected: device.presetId == preset.id)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(assignmentName(for: device))
                        .font(.footnote)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                renameText = device.name
                renamingDevice = device
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deviceStore.remove(device)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func assignmentLabel(_ name: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(name, systemImage: "checkmark")
        } else {
            Text(name)
        }
    }

    private func assignmentName(for device: EQDeviceProfile) -> String {
        guard let presetId = device.presetId,
              let preset = eqSettings.presets.first(where: { $0.id == presetId }) else {
            return "Default"
        }
        return preset.name
    }
}
