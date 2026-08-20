//
//  VolumeSliderView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import SwiftUI
#if canImport(UIKit)
import MediaPlayer

/// Wraps the system volume slider (MPVolumeView) so dragging it controls the device's
/// actual output volume, rather than a local AVPlayer volume that would diverge from it.
struct VolumeSliderView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        MPVolumeView(frame: .zero)
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
#endif
