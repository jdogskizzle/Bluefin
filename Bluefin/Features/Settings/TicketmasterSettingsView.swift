//
//  TicketmasterSettingsView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/23/26.
//

import SwiftUI

struct TicketmasterSettingsView: View {
    @ObservedObject private var client = TicketmasterAPIClient.shared
    @ObservedObject private var blacklistStore = TicketmasterBlacklistStore.shared
    @State private var apiKeyString = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if client.isConnected {
                Section {
                    Button("Disconnect", role: .destructive) {
                        client.disconnect()
                    }
                } footer: {
                    Text("Upcoming concerts for artists in your library will appear on the Home screen.")
                }
            }

            Section {
                NavigationLink {
                    TicketmasterBlacklistView()
                } label: {
                    HStack {
                        Text("Blacklisted Artists")
                        Spacer()
                        if !blacklistStore.blacklistedArtists.isEmpty {
                            Text("\(blacklistStore.blacklistedArtists.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !client.isConnected {
                Text("Connect to Ticketmaster to see upcoming concert dates for followed artists")
                Section {
                    SecureField("API Key", text: $apiKeyString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
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
                    .disabled(isConnecting || apiKeyString.isEmpty)
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        instructionRow(number: 1, text: "Go to [developer.ticketmaster.com](https://developer.ticketmaster.com) and sign in, or register for a free account.")
                        instructionRow(number: 2, text: "Click your username in the top-left corner, then choose \"My Apps.\" Ticketmaster automatically creates an app for you there.")
                        instructionRow(number: 3, text: "Click that app to expand it, then copy the \"Consumer Key\" and paste it above.")
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Getting an API Key")
                } footer: {
                    Text("""
                    Ticketmaster's free tier is per-key, not shared, so every Bluefin user needs their own key rather than one built into the app.

                    Ticketmaster's own "copy" button on that page doesn't always work. If the key gets rejected, try manually selecting and copying the text instead.
                    """)
                }
            }
        }
        .avoidsMiniPlayer()
        .navigationTitle("Ticketmaster")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func instructionRow(number: Int, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
        }
    }

    private func connect() {
        errorMessage = nil
        isConnecting = true
        Task {
            do {
                try await client.connect(apiKey: apiKeyString)
            } catch {
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }
}
