//
//  ToastOverlay.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import SwiftUI

/// Renders whatever `ToastCenter` currently has queued. Attach once per presentation layer — the
/// main tab chrome and the modally-presented large player each need their own, since a sheet fully
/// obscures whatever overlay lives behind it.
struct ToastOverlay: View {
    @ObservedObject private var center = ToastCenter.shared

    var body: some View {
        VStack {
            Spacer()
            if let toast = center.current {
                Text(toast.message)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(toast.isError ? Color.red : Color.black.opacity(0.85), in: Capsule())
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
    }
}
