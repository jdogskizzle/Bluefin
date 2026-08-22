//
//  SongDetailsView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/22/26.
//

import SwiftUI

struct SongDetailsView: View {
    let song: BaseItemDto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    detailRow("Name", song.Name)
                    detailRow("Album", song.Album)
                    detailRow("Artist", song.AlbumArtist ?? song.Artists?.first)
                    detailRow("Date Added", formattedDateAdded)
                }

                Section("Audio") {
                    detailRow("Codec", song.primaryAudioStream?.Codec?.uppercased())
                    detailRow("Bitrate", formattedBitrate)
                    detailRow("Sample Rate", formattedSampleRate)
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value?.isEmpty == false ? value! : "—")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var formattedDateAdded: String? {
        song.dateCreated?.formatted(date: .abbreviated, time: .shortened)
    }

    private var formattedBitrate: String? {
        guard let bitRate = song.primaryAudioStream?.BitRate else { return nil }
        return "\(bitRate / 1000) kbps"
    }

    private var formattedSampleRate: String? {
        guard let sampleRate = song.primaryAudioStream?.SampleRate else { return nil }
        return String(format: "%.1f kHz", Double(sampleRate) / 1000)
    }
}
