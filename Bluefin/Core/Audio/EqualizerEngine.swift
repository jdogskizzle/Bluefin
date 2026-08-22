//
//  EqualizerEngine.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/21/26.
//

import AVFoundation
import Foundation

/// Runs the actual per-sample EQ processing. Lives off the main actor on purpose: `process(...)` is
/// called from the `MTAudioProcessingTap`'s real-time audio thread (see `EqualizerAudioMixFactory`),
/// which can't hop to the main actor without risking an audible glitch, so every access here goes
/// through a plain lock instead of Combine/`@Published`. `EqualizerSettings` (main-actor, UI-facing)
/// pushes its state into this engine via `updateSettings` whenever it changes.
nonisolated final class EqualizerEngine: @unchecked Sendable {
    static let shared = EqualizerEngine()

    private let lock = NSLock()
    private var isEnabled = false
    private var gains = EqualizerBands.flatGains
    private var sampleRate: Double = 44100
    private var channelFilters: [[BiquadFilter]] = []

    private init() {}

    nonisolated func updateSettings(isEnabled: Bool, gains: [Double]) {
        lock.lock()
        defer { lock.unlock() }
        self.isEnabled = isEnabled
        self.gains = gains
        rebuildFilters()
    }

    nonisolated func prepare(sampleRate: Double, channelCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        self.sampleRate = sampleRate
        channelFilters = (0..<max(channelCount, 1)).map { _ in makeBandFilters() }
    }

    /// Reconfigures each existing filter's coefficients in place rather than replacing them —
    /// replacing would reset their delay-line state, producing an audible click on every slider
    /// drag tick instead of a smooth gain change.
    private func rebuildFilters() {
        for channel in channelFilters.indices {
            for band in channelFilters[channel].indices {
                channelFilters[channel][band].configure(frequency: EqualizerBands.frequencies[band], gainDB: gains[band], sampleRate: sampleRate)
            }
        }
    }

    private func makeBandFilters() -> [BiquadFilter] {
        EqualizerBands.frequencies.enumerated().map { index, frequency in
            BiquadFilter(frequency: frequency, gainDB: gains[index], sampleRate: sampleRate)
        }
    }

    nonisolated func process(bufferList: UnsafeMutableAudioBufferListPointer, frameCount: Int, interleaved: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard isEnabled, !channelFilters.isEmpty else { return }

        if interleaved {
            guard let buffer = bufferList.first, let data = buffer.mData else { return }
            let channelCount = Int(buffer.mNumberChannels)
            let samples = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                for channel in 0..<channelCount where channel < channelFilters.count {
                    let index = frame * channelCount + channel
                    var bandFilters = channelFilters[channel]
                    var sample = samples[index]
                    for band in bandFilters.indices {
                        sample = bandFilters[band].process(sample)
                    }
                    samples[index] = sample
                    channelFilters[channel] = bandFilters
                }
            }
        } else {
            for (channelIndex, buffer) in bufferList.enumerated() where channelIndex < channelFilters.count {
                guard let data = buffer.mData else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                var bandFilters = channelFilters[channelIndex]
                for frame in 0..<frameCount {
                    var sample = samples[frame]
                    for band in bandFilters.indices {
                        sample = bandFilters[band].process(sample)
                    }
                    samples[frame] = sample
                }
                channelFilters[channelIndex] = bandFilters
            }
        }
    }
}
