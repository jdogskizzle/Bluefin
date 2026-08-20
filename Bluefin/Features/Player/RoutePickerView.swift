//
//  RoutePickerView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import SwiftUI
#if canImport(UIKit)
import AVKit

/// Wraps the system AirPlay/Bluetooth output picker (AVRoutePickerView), which presents
/// the route selection sheet itself on tap — no action wiring needed on our end.
struct RoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = .secondaryLabel
        view.activeTintColor = .tintColor
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
