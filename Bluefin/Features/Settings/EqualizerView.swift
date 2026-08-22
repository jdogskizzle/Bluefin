//
//  EqualizerView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/21/26.
//

import SwiftUI

struct EqualizerView: View {
    @ObservedObject private var settings = EqualizerSettings.shared
    @State private var showSaveAlert = false
    @State private var presetName = ""
    @State private var showPresetsSheet = false

    var body: some View {
        VStack(spacing: 24) {
            Toggle("Enable Equalizer", isOn: $settings.isEnabled)
                .padding(.horizontal)

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(EqualizerBands.frequencies.indices, id: \.self) { index in
                    VStack(spacing: 6) {
                        Text(gainLabel(for: settings.gains[index]))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(height: 14)

                        VerticalEQSlider(
                            value: Binding(
                                get: { settings.gains[index] },
                                set: { newValue in
                                    settings.gains[index] = newValue
                                    settings.activePresetId = nil
                                }
                            ),
                            range: EqualizerBands.gainRange
                        )
                        .frame(height: 180)

                        Text(frequencyLabel(for: EqualizerBands.frequencies[index]))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .disabled(!settings.isEnabled)
            .opacity(settings.isEnabled ? 1 : 0.4)

            if let activePresetId = settings.activePresetId,
               let activePreset = settings.presets.first(where: { $0.id == activePresetId }) {
                Text("Preset: \(activePreset.name)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Button("Reset") {
                    settings.resetToDefault()
                }

                Spacer()

                Button {
                    presetName = ""
                    showSaveAlert = true
                } label: {
                    Label("Save Preset", systemImage: "plus.circle")
                }

                Button {
                    showPresetsSheet = true
                } label: {
                    Label("Presets", systemImage: "list.bullet")
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
        .navigationTitle("Equalizer")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Save Preset", isPresented: $showSaveAlert) {
            TextField("Preset Name", text: $presetName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                settings.savePreset(named: presetName)
            }
        }
        .sheet(isPresented: $showPresetsSheet) {
            EqualizerPresetsView()
        }
    }

    private func gainLabel(for value: Double) -> String {
        if value == 0 { return "0" }
        return value > 0 ? String(format: "+%.1f", value) : String(format: "%.1f", value)
    }

    private func frequencyLabel(for frequency: Double) -> String {
        frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))"
    }
}

struct EqualizerPresetsView: View {
    @ObservedObject private var settings = EqualizerSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if settings.presets.isEmpty {
                    ContentUnavailableView(
                        "No Presets",
                        systemImage: "slider.horizontal.3",
                        description: Text("Save your current EQ settings as a preset to see it here.")
                    )
                } else {
                    List {
                        ForEach(settings.presets) { preset in
                            Button {
                                settings.loadPreset(preset)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(preset.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if settings.activePresetId == preset.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    settings.deletePreset(preset)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
