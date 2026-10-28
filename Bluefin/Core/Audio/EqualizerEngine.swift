//
//  EqualizerEngine.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/21/26.
//

import AVFoundation

/// Thin bridge between `EqualizerSettings` (persisted UI state) and the actual `AVAudioUnitEQ` node
/// living permanently in `AudioPlayerManager`'s engine graph. A native Core Audio unit, wired into
/// the graph once for the app's lifetime rather than attached/detached per track — unlike the custom
/// `MTAudioProcessingTap`-based DSP this replaced, there's nothing here that needs tearing down or
/// rebuilding at a track boundary, which is exactly what stood between this player and gapless
/// playback before. Adjusting a running `AVAudioUnitEQ`'s bands is also safe to do live, with no
/// locking needed the way the old hand-rolled biquad filters required.
@MainActor
final class EqualizerEngine {
    static let shared = EqualizerEngine()

    let node = AVAudioUnitEQ(numberOfBands: EqualizerBands.count)

    private init() {
        for (index, frequency) in EqualizerBands.frequencies.enumerated() {
            let band = node.bands[index]
            band.filterType = .parametric
            band.frequency = Float(frequency)
            band.bandwidth = 1.0
            band.bypass = false
        }
    }

    func updateSettings(isEnabled: Bool, gains: [Double]) {
        node.bypass = !isEnabled
        for (index, gain) in gains.enumerated() where index < node.bands.count {
            node.bands[index].gain = Float(gain)
        }
    }
}
