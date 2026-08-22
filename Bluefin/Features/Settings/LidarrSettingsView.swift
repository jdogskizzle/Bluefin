//
//  LidarrSettingsView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/21/26.
//

import SwiftUI

struct LidarrSettingsView: View {
    @ObservedObject private var client = LidarrAPIClient.shared
    @State private var serverURLString = ""
    @State private var apiKeyString = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if client.isConnected {
                Section {
                    HStack {
                        Text("Server")
                        Spacer()
                        Text(client.serverURL?.absoluteString ?? "")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Button("Disconnect", role: .destructive) {
                        client.disconnect()
                    }
                } footer: {
                    Text("Upcoming releases for followed artists will appear on the Home screen.")
                }
            } else {
                Section {
                    TextField("Server URL", text: $serverURLString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Key", text: $apiKeyString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    } else {
                        Text("Find your API key in Lidarr under Settings > General.")
                    }
                }

                Section {
                    Button {
                        connect()
                    } label: {
                        HStack {
                            Text("Connect")
                            if isConnecting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isConnecting || serverURLString.isEmpty || apiKeyString.isEmpty)
                }
            }
        }
        .navigationTitle("Lidarr")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func connect() {
        errorMessage = nil
        isConnecting = true
        Task {
            do {
                try await client.connect(urlString: serverURLString, apiKey: apiKeyString)
            } catch {
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }
}
