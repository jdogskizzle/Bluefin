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
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
