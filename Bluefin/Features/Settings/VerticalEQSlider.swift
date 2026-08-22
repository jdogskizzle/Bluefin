//
//  VerticalEQSlider.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/21/26.
//

import SwiftUI

/// A Spotify-style vertical EQ band slider: a filled capsule track growing up (boost) or down (cut)
/// from a center zero-line, with a draggable thumb.
struct VerticalEQSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    private let trackWidth: CGFloat = 6
    private let thumbDiameter: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let thumbY = position(for: value, height: height)
            let zeroY = position(for: 0, height: height)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: trackWidth)
                    .frame(maxWidth: .infinity)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: trackWidth, height: abs(zeroY - thumbY))
                    .frame(maxWidth: .infinity)
                    .offset(y: min(zeroY, thumbY))

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                    .frame(maxWidth: .infinity)
                    .offset(y: thumbY - thumbDiameter / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        value = value(for: drag.location.y, height: height)
                    }
            )
        }
    }

    private func position(for value: Double, height: CGFloat) -> CGFloat {
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return height * (1 - fraction)
    }

    private func value(for y: CGFloat, height: CGFloat) -> Double {
        let clampedY = min(max(0, y), height)
        let fraction = 1 - (clampedY / height)
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        return (raw * 2).rounded() / 2
    }
}
