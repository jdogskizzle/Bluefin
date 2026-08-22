//
//  QualitySettingsView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/22/26.
//

import SwiftUI

struct QualitySettingsView: View {
    @ObservedObject private var settings = StreamingQualitySettings.shared

    var body: some View {
        Form {
            Section {
                Picker("Wi-Fi Streaming", selection: $settings.wifiQuality) {
                    ForEach(StreamingQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
                Picker("Cellular Streaming", selection: $settings.cellularQuality) {
                    ForEach(StreamingQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
            } footer: {
                Text("Original streams the file untouched. Lower bitrates are transcoded by the server, using less data at some cost to audio quality.")
            }

            Section {
                Picker("Download Quality", selection: $settings.downloadQuality) {
                    ForEach(StreamingQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
            } footer: {
                Text("Applies to songs, albums, artists, and playlists you download.")
            }
        }
        .navigationTitle("Quality")
        .navigationBarTitleDisplayMode(.inline)
    }
}
