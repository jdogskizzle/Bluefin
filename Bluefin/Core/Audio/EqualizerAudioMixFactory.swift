//
//  EqualizerAudioMixFactory.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/21/26.
//

import AVFoundation
import CoreMedia
import MediaToolbox

/// Bridges an `AVPlayerItem`'s audio track into `EqualizerEngine` via `MTAudioProcessingTap` — the
/// only public way to run custom per-sample DSP on `AVPlayer` audio without giving up its built-in
/// streaming/caching/seek/lock-screen machinery.
enum EqualizerAudioMixFactory {
    static func makeAudioMix(for asset: AVAsset) async -> AVAudioMix? {
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else { return nil }

        let context = TapContext(engine: EqualizerEngine.shared)
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(context).toOpaque(),
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr, let tap else { return nil }

        let params = AVMutableAudioMixInputParameters(track: audioTrack)
        params.audioTapProcessor = tap

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [params]
        return audioMix
    }
}

/// Per-tap state bridged through the C callbacks via `MTAudioProcessingTapGetStorage` — the format
/// (channel count / interleaving) is only known once `tapPrepare` runs, so it's cached here rather
/// than re-derived every `tapProcess` call.
private nonisolated final class TapContext {
    let engine: EqualizerEngine
    var isInterleaved = false

    init(engine: EqualizerEngine) {
        self.engine = engine
    }
}

private nonisolated func tapInit(
    tap: MTAudioProcessingTap,
    clientInfo: UnsafeMutableRawPointer?,
    tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

private nonisolated func tapFinalize(tap: MTAudioProcessingTap) {
    Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private nonisolated func tapPrepare(
    tap: MTAudioProcessingTap,
    maxFrames: CMItemCount,
    processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    let context = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    let format = processingFormat.pointee
    context.isInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
    context.engine.prepare(sampleRate: format.mSampleRate, channelCount: Int(format.mChannelsPerFrame))
}

private nonisolated func tapUnprepare(tap: MTAudioProcessingTap) {}

private nonisolated func tapProcess(
    tap: MTAudioProcessingTap,
    numberFrames: CMItemCount,
    flags: MTAudioProcessingTapFlags,
    bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    var timeRange = CMTimeRange.zero
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, &timeRange, numberFramesOut)
    guard status == noErr else { return }

    let context = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    let bufferList = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    context.engine.process(bufferList: bufferList, frameCount: Int(numberFrames), interleaved: context.isInterleaved)
}
