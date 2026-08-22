//
//  BiquadFilter.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/21/26.
//

import Foundation

/// A single peaking-EQ biquad stage (RBJ Audio EQ Cookbook), boosting or cutting a band centered on
/// `frequency` by `gainDB` with bandwidth controlled by `q`. One octave of bandwidth (`q` ≈ 1.41)
/// suits the roughly-octave spacing of `EqualizerBands.frequencies`.
nonisolated struct BiquadFilter {
    private var b0: Double = 1
    private var b1: Double = 0
    private var b2: Double = 0
    private var a1: Double = 0
    private var a2: Double = 0

    private var x1: Double = 0
    private var x2: Double = 0
    private var y1: Double = 0
    private var y2: Double = 0

    init(frequency: Double, gainDB: Double, sampleRate: Double, q: Double = 1.41) {
        configure(frequency: frequency, gainDB: gainDB, sampleRate: sampleRate, q: q)
    }

    mutating func configure(frequency: Double, gainDB: Double, sampleRate: Double, q: Double = 1.41) {
        guard gainDB != 0, sampleRate > 0 else {
            b0 = 1; b1 = 0; b2 = 0; a1 = 0; a2 = 0
            return
        }

        let a = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosw0 = cos(w0)
        let alpha = sin(w0) / (2 * q)

        let a0 = 1 + alpha / a
        b0 = (1 + alpha * a) / a0
        b1 = (-2 * cosw0) / a0
        b2 = (1 - alpha * a) / a0
        a1 = (-2 * cosw0) / a0
        a2 = (1 - alpha / a) / a0
    }

    mutating func process(_ input: Float) -> Float {
        let x0 = Double(input)
        let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x0
        y2 = y1
        y1 = y0
        return Float(y0)
    }

    mutating func reset() {
        x1 = 0; x2 = 0; y1 = 0; y2 = 0
    }
}
