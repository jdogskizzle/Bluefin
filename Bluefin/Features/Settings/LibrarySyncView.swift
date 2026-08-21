//
//  LibrarySyncView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Combine
import SwiftUI

/// Sheet presented from Settings for the explicit, blocking library sync — the only thing that
/// ever populates the library-browsing screens with data. Dismissal is disabled while a sync is
/// running so it reads as the blocking action it is, rather than something to abandon partway.
struct LibrarySyncView: View {
    @ObservedObject private var manager = LibrarySyncManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)

                statusText

                if manager.isSyncing {
                    VStack(spacing: 8) {
                        ProgressView(value: manager.overallProgress)
                            .frame(maxWidth: 240)
                        Text(stepStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    Task { await manager.sync() }
                } label: {
                    Text(manager.isSyncing ? "Syncing…" : "Sync Now")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.isSyncing)
                .padding(.bottom, 24)
            }
            .padding()
            .navigationTitle("Sync Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(manager.isSyncing)
                }
            }
        }
        .interactiveDismissDisabled(manager.isSyncing)
    }

    @ViewBuilder
    private var statusText: some View {
        switch manager.phase {
        case .idle:
            if let lastSyncedAt = manager.lastSyncedAt {
                Text("Last synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(.secondary)
            } else {
                Text("Your library hasn't been synced yet.")
                    .foregroundStyle(.secondary)
            }
        case .syncing:
            Text("Syncing your library…")
                .fontWeight(.medium)
        case .finished:
            Label("Synced", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private var stepStatusText: String {
        guard case .syncing(let step, let completed, let total) = manager.phase else { return "" }
        guard total > 1 else { return "Fetching \(step.rawValue.lowercased())…" }
        return "\(step.rawValue) (\(completed)/\(total))"
    }
}

struct LibrarySyncView_Previews: PreviewProvider {
    static var previews: some View {
        LibrarySyncView()
    }
}
