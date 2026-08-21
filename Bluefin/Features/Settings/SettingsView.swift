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
            }

            Section("Storage") {
                HStack {
                    Text("Cached Audio")
                    Spacer()
                    Text(viewModel.formattedCacheSize)
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
                Button("Clear Cache", role: .destructive) {
                    Task { await viewModel.clearCache() }
                }
                .disabled(viewModel.isClearingCache || viewModel.cacheSizeBytes == 0)
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
                Button("Sign Out", role: .destructive) {
                    viewModel.signOut()
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            await viewModel.loadLibraries()
            await viewModel.refreshCacheSize()
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
