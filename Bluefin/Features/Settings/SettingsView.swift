//
//  SettingsView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel(apiClient: .shared)
    @ObservedObject private var apiClient = JellyfinAPIClient.shared
    @ObservedObject private var syncManager = LibrarySyncManager.shared
    @ObservedObject private var eqSettings = EqualizerSettings.shared
    @ObservedObject private var lidarrClient = LidarrAPIClient.shared
    @State private var showSync = false

    var body: some View {
        Form {
            Section("Music Library") {
                if viewModel.isLoading {
                    ProgressView()
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.secondary)
                } else if viewModel.musicLibraries.isEmpty {
                    Text("No music libraries found on this server.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.musicLibraries) { library in
                        Button {
                            viewModel.select(library)
                        } label: {
                            HStack {
                                Text(library.Name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if library.Id == apiClient.selectedLibraryId {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
                if apiClient.selectedLibraryId != nil {
                    HStack {
                        Text("Artists")
                        Spacer()
                        Text("\(viewModel.artistCount)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Albums")
                        Spacer()
                        Text("\(viewModel.albumCount)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Songs")
                        Spacer()
                        Text("\(viewModel.songCount)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Playlists")
                        Spacer()
                        Text("\(viewModel.playlistCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Library Sync") {
                Button {
                    showSync = true
                } label: {
                    HStack {
                        Text("Sync Library")
                        Spacer()
                        if let lastSyncedAt = syncManager.lastSyncedAt {
                            Text(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        } else {
                            Text("Never")
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        }
                    }
                }
            }

            Section {
                HStack {
                    Text("Cached Audio")
                    Spacer()
                    Text(viewModel.formattedCacheSize)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Cached Library")
                    Spacer()
                    Text(viewModel.formattedLibrarySize)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Downloaded Songs")
                    Spacer()
                    Text("\(viewModel.downloadedSongCount)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Downloads Size")
                    Spacer()
                    Text(viewModel.formattedDownloadsSize)
                        .foregroundStyle(.secondary)
                }
                Picker("Cache Limit", selection: $viewModel.cacheLimitBytes) {
                    Text("1 GB").tag(Int64(1_000_000_000))
                    Text("2 GB").tag(Int64(2_000_000_000))
                    Text("5 GB").tag(Int64(5_000_000_000))
                    Text("10 GB").tag(Int64(10_000_000_000))
                }
                Picker("Pre-cache Ahead", selection: $viewModel.preCacheLookahead) {
                    Text("5 tracks").tag(5)
                    Text("10 tracks").tag(10)
                    Text("15 tracks").tag(15)
                    Text("20 tracks").tag(20)
                }
                Button("Clear Audio Cache", role: .destructive) {
                    Task { await viewModel.clearCache() }
                }
                .disabled(viewModel.isClearingCache || viewModel.cacheSizeBytes == 0)
                Button("Clear Downloads", role: .destructive) {
                    Task { await viewModel.clearDownloads() }
                }
                .disabled(viewModel.isClearingDownloads || viewModel.downloadsSizeBytes == 0)
            } header: {
                Text("Storage")
            } footer: {
                Text("Clearing the audio cache only removes opportunistically cached audio, not songs you've explicitly downloaded.")
            }

            Section("Playback") {
                NavigationLink {
                    EqualizerView()
                } label: {
                    HStack {
                        Text("Equalizer")
                        Spacer()
                        Text(eqSettings.isEnabled ? "On" : "Off")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }
                NavigationLink {
                    QualitySettingsView()
                } label: {
                    Text("Quality")
                }
            }

            Section("Account") {
                if let serverURL = apiClient.serverURL {
                    HStack {
                        Text("Server")
                        Spacer()
                        Text(serverURL.absoluteString)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                NavigationLink {
                    LidarrSettingsView()
                } label: {
                    HStack {
                        Text("Lidarr")
                        Spacer()
                        Text(lidarrClient.isConnected ? "Connected" : "Not Connected")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }
                Button("Sign Out", role: .destructive) {
                    viewModel.signOut()
                }
            }
        }
        .avoidsMiniPlayer()
        .navigationTitle("Settings")
        .task {
            await viewModel.loadLibraries()
            await viewModel.refreshCacheSize()
            await viewModel.refreshLibrarySize()
            await viewModel.refreshDownloadsSize()
            await viewModel.refreshLibraryCounts()
        }
        .sheet(isPresented: $showSync) {
            LibrarySyncView()
        }
        .onChange(of: showSync) { _, isShowing in
            guard !isShowing else { return }
            Task {
                await viewModel.refreshLibrarySize()
                await viewModel.refreshLibraryCounts()
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
