//
//  ToastCenter.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Combine
import SwiftUI

/// A brief, self-dismissing message at the bottom of the screen — used for background actions
/// (like adding a song to a playlist) that shouldn't block the UI but still need to report success
/// or failure once the server actually confirms it.
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    @Published private(set) var current: Toast?

    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ message: String, isError: Bool = false) {
        dismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) {
            current = Toast(message: message, isError: isError)
        }
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                current = nil
            }
        }
    }
}
