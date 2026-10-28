//
//  AudioPlayerManager.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import AVFoundation
import Combine
import MediaPlayer
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    static let shared = AudioPlayerManager()

    @Published private(set) var queue: [BaseItemDto] = [] { didSet { persistPlaybackState() } }
    /// A stable id per queue *slot*, parallel to `queue` (same length, same order) — not per song,
    /// since the same song can appear in the queue more than once. `QueueView` uses this instead of
    /// position as its `ForEach` identity, so a reorder is diffed as "this row moved" rather than
    /// "the content at each position changed," which is what SwiftUI needs to animate a drag-drop
    /// smoothly instead of visibly re-settling into place after the drop. Every mutation to `queue`
    /// keeps this in lockstep: `insertQueueItem`/`removeQueueItem`/`replaceQueue` below for
    /// inserting/removing an entry, or (in `moveInQueue`) moving an id alongside its entry so a
    /// reordered row keeps the *same* id rather than being treated as removed-and-reinserted.
    @Published private(set) var queueEntryIDs: [UUID] = []
    /// `didSet` here (and on `currentIndex`/`subqueueCount` below) is what makes persistence
    /// automatic for every mutation path — `play(queue:)`, `addToSubqueue`, `removeFromQueue`,
    /// `applyQueueReorder`, skip/jump — rather than needing a `persistPlaybackState()` call added
    /// at each one individually and risking a future mutation path forgetting it.
    @Published private(set) var currentIndex: Int = 0 { didSet { persistPlaybackState() } }
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    /// True from the moment a track is asked to play until audio is actually flowing — covers the
    /// network fetch (ensuring a local file exists) and local decode setup. Drives a loading
    /// animation in place of the scrubber in `NowPlayingView`, since there's no meaningful
    /// percentage to show for a network fetch — just that something is happening.
    @Published private(set) var isLoadingTrack: Bool = false
    /// How many of the entries immediately after `currentIndex` were manually queued via "Add to
    /// Queue" — always the contiguous run `[currentIndex+1, currentIndex+1+subqueueCount)`. That
    /// invariant is what makes a plain count sufficient instead of tracking membership per item:
    /// every mutation (add/remove/reorder) is defined in terms of this same contiguous range.
    @Published private(set) var subqueueCount: Int = 0 { didSet { persistPlaybackState() } }

    var currentItem: BaseItemDto? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }

    func isIndexInSubqueue(_ index: Int) -> Bool {
        guard subqueueCount > 0 else { return false }
        return (currentIndex + 1..<currentIndex + 1 + subqueueCount).contains(index)
    }

    private func replaceQueue(_ newQueue: [BaseItemDto]) {
        queue = newQueue
        queueEntryIDs = newQueue.map { _ in UUID() }
    }

    private func insertQueueItem(_ item: BaseItemDto, at index: Int) {
        queue.insert(item, at: index)
        queueEntryIDs.insert(UUID(), at: index)
    }

    @discardableResult
    private func removeQueueItem(at index: Int) -> BaseItemDto {
        queueEntryIDs.remove(at: index)
        return queue.remove(at: index)
    }

    // MARK: - Playback engine
    //
    // Gapless playback between consecutive songs is only guaranteed by actually feeding one
    // continuous stream of PCM samples to the audio hardware, with nothing in between — not by
    // asking a higher-level player (`AVPlayer`/`AVQueuePlayer`) to switch its "current item" at the
    // boundary, even with the next item fully pre-buffered. That switch always involves tearing
    // down one compressed-audio decode session and starting another, which is not specified (and in
    // practice isn't reliable here) to be sample-accurate. `AVAudioEngine` + `AVAudioPlayerNode`
    // sidesteps this entirely: every track, regardless of its source format, is decoded to PCM and
    // scheduled onto the *same* node back-to-back, so a track boundary is nothing more than "which
    // chunk of samples this happens to be" from the node's perspective — there is no hand-off to get
    // wrong. This also removes the equalizer's old per-item `MTAudioProcessingTap`/`AVAudioMix`
    // (which needed rebuilding at every item boundary) in favor of a single `AVAudioUnitEQ` node
    // permanently wired into the graph (see `EqualizerEngine`).
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let canonicalFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    /// Each chunk's `.dataConsumed` completion hops back through a `Task` to the main actor before
    /// the next chunk gets scheduled — if that hop is ever delayed (SwiftUI work, the time-update
    /// timer, anything else on the main actor), the node can run dry for a moment with nothing queued
    /// behind the chunk that just finished, which is audible as a click right at the chunk boundary.
    /// Keeping this many chunks scheduled ahead at all times (see `beginScheduling`) gives that hop
    /// slack to be late without the node ever actually running out of audio.
    private let chunkDurationSeconds: Double = 4.0
    private let targetBufferedChunks = 3

    /// Opaque identity for "one track's decode/schedule chain" — deliberately not a queue index,
    /// since `removeFromQueue`/reorders can shift indices out from under an in-flight chain. Bumped
    /// for every new chain, whether started by `startPlayback` or by `prepareNextTrack`'s hand-off.
    private var nextDecodeSessionId = 0
    /// The session whose audio is the one actually mapped to `currentIndex` right now.
    private var activeDecodeSession = 0
    /// Bumped on every *discontinuous* restart (manual skip/seek/jump/queue-replace) — every
    /// in-flight async step and scheduled-buffer completion closure checks this before touching
    /// state, so stale work from a superseded chain can't corrupt the new one.
    private var decodeGeneration = 0

    /// The next track's feeder/session/item, once `prepareNextTrack` has it ready and its first
    /// chunk is already scheduled onto `playerNode` — `handleTrackFinishedRendering` just needs to
    /// flip `activeDecodeSession` to match what the engine already gaplessly moved on to. `nil` until
    /// ready, and also whenever nothing is prepared (e.g. still mid-download).
    private var pendingNextSession: Int?
    private var pendingNextItem: BaseItemDto?

    /// Node-timeline frame offset at which each session's audio started — the engine's own sample
    /// clock runs continuously across every track played in one session, so this is what turns that
    /// into a track-relative "current time." Removed once a session finishes.
    private var trackStartFrames: [Int: AVAudioFramePosition] = [:]
    /// How far into a track's own content, in frames, a session's audio actually started — nonzero
    /// only when that session began via a seek (`startPlayback`'s `resumeAt`). `trackStartFrames`
    /// alone can't capture this: after a seek the node's clock is reset to 0 by `playerNode.stop()`,
    /// so without this offset `refreshCurrentTime` would compute time-since-restart instead of the
    /// actual seeked-to position, snapping the displayed/reported time back toward 0 right after
    /// every seek.
    private var sessionStartOffsetFrames: [Int: AVAudioFramePosition] = [:]
    private var framesScheduledSoFar: AVAudioFramePosition = 0
    private var timeUpdateTimer: Timer?

    /// Streams one track's audio a few seconds at a time via `AVAudioFile` (so a multi-minute song
    /// doesn't need to be decoded into memory up front), converting to the engine's canonical format
    /// on the way out since a mixed-format library (different sample rates/channel counts between
    /// tracks) can't otherwise be scheduled onto the same player node.
    private final class TrackFeeder {
        private let audioFile: AVAudioFile
        private let converter: AVAudioConverter?
        private let outputFormat: AVAudioFormat
        private(set) var isExhausted = false

        init(fileURL: URL, outputFormat: AVAudioFormat, seekSeconds: TimeInterval = 0) throws {
            let file = try AVAudioFile(forReading: fileURL)
            self.audioFile = file
            self.outputFormat = outputFormat
            if seekSeconds > 0 {
                let frame = AVAudioFramePosition(seekSeconds * file.processingFormat.sampleRate)
                file.framePosition = max(0, min(frame, file.length))
            }
            let source = file.processingFormat
            if source.sampleRate == outputFormat.sampleRate, source.channelCount == outputFormat.channelCount {
                converter = nil
            } else {
                guard let converter = AVAudioConverter(from: source, to: outputFormat) else {
                    throw NSError(domain: "Bluefin.TrackFeeder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format for \(fileURL.lastPathComponent)"])
                }
                self.converter = converter
            }
        }

        /// Reads roughly `approximateSeconds` of source audio, converted to `outputFormat` — `nil`
        /// once nothing more can be read. Sets `isExhausted` on the same call that returns the final
        /// partial chunk, so the caller never needs an extra round-trip just to discover a track has
        /// ended.
        func readChunk(approximateSeconds: Double) -> AVAudioPCMBuffer? {
            guard !isExhausted else { return nil }
            let sourceFormat = audioFile.processingFormat
            let framesToRead = AVAudioFrameCount(max(1, sourceFormat.sampleRate * approximateSeconds))
            guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: framesToRead) else {
                isExhausted = true
                return nil
            }
            do {
                try audioFile.read(into: sourceBuffer, frameCount: framesToRead)
            } catch {
                isExhausted = true
                return nil
            }
            if sourceBuffer.frameLength < framesToRead {
                isExhausted = true
            }
            guard sourceBuffer.frameLength > 0 else { return nil }
            guard let converter else { return sourceBuffer }

            let ratio = outputFormat.sampleRate / sourceFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio) + 8
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
                return sourceBuffer
            }

            var hasServedInput = false
            var conversionError: NSError?
            converter.convert(to: convertedBuffer, error: &conversionError) { _, inputStatus in
                if hasServedInput {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                hasServedInput = true
                inputStatus.pointee = .haveData
                return sourceBuffer
            }
            return conversionError == nil ? convertedBuffer : nil
        }
    }

    private var backgroundObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var engineConfigChangeObserver: NSObjectProtocol?
    private var wasPlayingBeforeInterruption = false

    /// The Jellyfin play session currently being reported, if any — `nil` until playback actually
    /// starts for the loaded item (e.g. a paused, app-launch-restored track has none yet), and
    /// cleared once a `Sessions/Playing/Stopped` report has been sent for it.
    private var activeReportingSession: (itemId: String, sessionId: String)?
    private var lastProgressReportTime: TimeInterval = 0
    private let progressReportInterval: TimeInterval = 10

    private struct PersistedPlaybackState: Codable {
        let queue: [BaseItemDto]
        let currentIndex: Int
        let currentTime: TimeInterval
        let subqueueCount: Int
    }

    private static let playbackStateDefaultsKey = "com.bluefin.playbackState"

    private override init() {
        super.init()
        configureAudioSession()
        buildEngineGraph()
        configureRemoteCommandCenter()
        startTimeUpdates()
        observeAppBackgrounding()
        observeRouteChanges()
        observeInterruptions()
        restorePlaybackState()
    }

    /// Wires `playerNode -> EqualizerEngine's AVAudioUnitEQ -> mainMixer` once, for the lifetime of
    /// the app — nothing here is ever torn down or rebuilt per track, which is exactly what made the
    /// old per-item `MTAudioProcessingTap` approach (and before that, the item-switch itself) a
    /// source of audible hiccups at track boundaries.
    private func buildEngineGraph() {
        let eqNode = EqualizerEngine.shared.node
        engine.attach(playerNode)
        engine.attach(eqNode)
        engine.connect(playerNode, to: eqNode, format: canonicalFormat)
        engine.connect(eqNode, to: engine.mainMixerNode, format: canonicalFormat)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    private func startTimeUpdates() {
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshCurrentTime()
            }
        }
    }

    private func refreshCurrentTime() {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              let startFrame = trackStartFrames[activeDecodeSession] else { return }
        let elapsedFrames = playerTime.sampleTime - startFrame
        currentTime = max(0, Double(elapsedFrames) / canonicalFormat.sampleRate)
        if isPlaying, currentTime - lastProgressReportTime >= progressReportInterval {
            lastProgressReportTime = currentTime
            reportProgress(isPaused: false)
        }
    }

    /// Headphones/Bluetooth disconnecting mid-playback already makes iOS stop routing audio out loud
    /// — but nothing here was watching for that, so this manager's own `isPlaying` state (and every
    /// UI built on it: the mini player, Now Playing, lock-screen controls) kept reading "playing" for
    /// audio that had actually already stopped. Pausing here keeps that state honest.
    private func observeRouteChanges() {
        #if canImport(UIKit)
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else { return }
            Task { @MainActor [weak self] in
                self?.handleRouteChange(reasonValue: reasonValue)
            }
        }
        #endif
    }

    #if canImport(UIKit)
    private func handleRouteChange(reasonValue: UInt) {
        guard let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
              reason == .oldDeviceUnavailable, isPlaying else { return }
        pause()
    }
    #endif

    /// `AVPlayer` absorbed phone-call/Siri interruptions and audio-route hardware-format changes
    /// invisibly; `AVAudioEngine` does not — an interruption stops the engine outright, and it has
    /// to be explicitly restarted afterward, or playback silently never resumes.
    private func observeInterruptions() {
        #if canImport(UIKit)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            Task { @MainActor [weak self] in
                self?.handleInterruption(notification: notification)
            }
        }
        engineConfigChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.handleEngineConfigurationChange()
            }
        }
        #endif
    }

    #if canImport(UIKit)
    private func handleInterruption(notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying { pause() }
        case .ended:
            let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
            if wasPlayingBeforeInterruption, shouldResume {
                resume()
            }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    private func handleEngineConfigurationChange() {
        guard isPlaying, !engine.isRunning else { return }
        try? engine.start()
    }
    #endif

    /// Backgrounding is the reliable "the user is done with the app for now" signal — a force-quit
    /// from the app switcher requires backgrounding first, so this reliably catches it. Queue/index/
    /// subqueue changes persist immediately on their own via `didSet` above; `currentTime` doesn't
    /// (it'd mean a UserDefaults write ~2x/second while playing), so this is what captures a
    /// reasonably fresh position for it.
    private func observeAppBackgrounding() {
        #if canImport(UIKit)
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.persistPlaybackState()
                self?.reportProgress(isPaused: !(self?.isPlaying ?? false))
            }
        }
        #endif
    }

    private func persistPlaybackState() {
        guard queue.indices.contains(currentIndex) else {
            UserDefaults.standard.removeObject(forKey: Self.playbackStateDefaultsKey)
            return
        }
        let state = PersistedPlaybackState(queue: queue, currentIndex: currentIndex, currentTime: currentTime, subqueueCount: subqueueCount)
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.playbackStateDefaultsKey)
    }

    /// Restores the last session's queue and position, prepared paused — resuming playback
    /// automatically on launch would be a surprising thing for the app to do on its own.
    private func restorePlaybackState() {
        guard let data = UserDefaults.standard.data(forKey: Self.playbackStateDefaultsKey),
              let state = try? JSONDecoder().decode(PersistedPlaybackState.self, from: data),
              state.queue.indices.contains(state.currentIndex) else { return }

        // Set first: `queue`/`currentIndex`/`subqueueCount` below each redundantly re-persist the
        // whole state via `didSet` as they're assigned, so `currentTime` needs to already be correct
        // before that happens rather than briefly writing back a stale 0.
        currentTime = state.currentTime
        replaceQueue(state.queue)
        currentIndex = state.currentIndex
        subqueueCount = state.subqueueCount
        startPlayback(atQueueIndex: state.currentIndex, autoplay: false, resumeAt: state.currentTime)
    }

    func play(queue newQueue: [BaseItemDto], startAt index: Int) {
        guard newQueue.indices.contains(index) else { return }
        replaceQueue(newQueue)
        currentIndex = index
        subqueueCount = 0
        startPlayback(atQueueIndex: index, autoplay: true)
    }

    /// Jumps to a track already in the current queue, leaving the rest of the queue unchanged.
    /// Jumping forward into (or past) the subqueue consumes whatever of it was skipped over;
    /// jumping backward into history leaves the subqueue as-is, since there's nothing meaningful
    /// to restore about a song's subqueue membership once it's already been played past.
    func play(at index: Int) {
        guard queue.indices.contains(index), index != currentIndex else { return }
        if index > currentIndex {
            let oldSubqueueEnd = currentIndex + 1 + subqueueCount
            subqueueCount = index < oldSubqueueEnd ? max(0, oldSubqueueEnd - index - 1) : 0
        }
        currentIndex = index
        startPlayback(atQueueIndex: index, autoplay: true)
    }

    /// Inserts `song` right after the current song, or after the last existing "Add to Queue" item
    /// if there already is one — building up a contiguous subqueue rather than scattering additions
    /// throughout the rest of the queue.
    func addToSubqueue(_ song: BaseItemDto) {
        addToSubqueue([song])
    }

    /// Same as `addToSubqueue(_:BaseItemDto)`, but for a whole batch (e.g. "Add Album to Queue") —
    /// inserted contiguously in order with a single queue mutation, rather than one insert (and one
    /// persisted-state write) per song.
    func addToSubqueue(_ songs: [BaseItemDto]) {
        guard !songs.isEmpty else { return }
        guard !queue.isEmpty else {
            play(queue: songs, startAt: 0)
            return
        }
        let insertIndex = min(currentIndex + 1 + subqueueCount, queue.count)
        var newQueue = queue
        var newEntryIDs = queueEntryIDs
        newQueue.insert(contentsOf: songs, at: insertIndex)
        newEntryIDs.insert(contentsOf: songs.map { _ in UUID() }, at: insertIndex)
        queue = newQueue
        queueEntryIDs = newEntryIDs
        subqueueCount += songs.count
    }

    /// Removes an upcoming (not currently-playing) queue entry.
    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index), index != currentIndex else { return }
        let wasInSubqueue = isIndexInSubqueue(index)
        removeQueueItem(at: index)
        if index < currentIndex {
            currentIndex -= 1
        } else if wasInSubqueue {
            subqueueCount = max(0, subqueueCount - 1)
        }
    }

    /// Applies a queue reorder the caller already performed (see `QueueView`, which splices using
    /// SwiftUI's own `Array.move(fromOffsets:toOffset:)` — the exact primitive `List`'s native
    /// drag-reorder assumes downstream code uses, so the result can't drift from what the drag
    /// gesture visually showed). `movedEntryID` locates the moved entry in the new array to
    /// determine whether it counts as "in the subqueue" afterward, purely by whether it landed
    /// inside that range — moving into it adds it, moving out removes it, moving within it is a
    /// no-op.
    ///
    /// Note there's no explicit "re-prepare the next track" step here (or in the two mutators
    /// above): `prepareNextTrack` below only ever runs right before it's actually needed and reads
    /// `queue[currentIndex + 1]` fresh at that moment, so it naturally reflects whatever the queue
    /// looks like by then rather than needing to be invalidated after every mutation.
    func applyQueueReorder(newQueue: [BaseItemDto], newEntryIDs: [UUID], movedEntryID: UUID, wasInSubqueue: Bool) {
        queue = newQueue
        queueEntryIDs = newEntryIDs
        guard let newIndex = newEntryIDs.firstIndex(of: movedEntryID) else { return }
        let isNowInSubqueue = isIndexInSubqueue(newIndex)
        if wasInSubqueue != isNowInSubqueue {
            subqueueCount = max(0, subqueueCount + (isNowInSubqueue ? 1 : -1))
        }
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        // A deliberate pause should hide the loading animation immediately, rather than waiting on
        // the load to finish — the user asked playback to stop, so it reads as done, not still
        // loading, even if the fetch technically hasn't finished.
        isLoadingTrack = false
        updateNowPlayingPlaybackState()
        persistPlaybackState()
        reportProgress(isPaused: true)
    }

    func resume() {
        if !engine.isRunning {
            try? engine.start()
        }
        playerNode.play()
        isPlaying = true
        updateNowPlayingPlaybackState()
        startReportingSessionIfNeeded()
        reportProgress(isPaused: false)
    }

    func skipToNext() {
        guard currentIndex + 1 < queue.count else { return }
        if subqueueCount > 0 {
            subqueueCount -= 1
        }
        currentIndex += 1
        startPlayback(atQueueIndex: currentIndex, autoplay: isPlaying)
    }

    func skipToPrevious() {
        if currentTime > 3 || currentIndex == 0 {
            seek(to: 0)
            return
        }
        currentIndex -= 1
        startPlayback(atQueueIndex: currentIndex, autoplay: isPlaying)
    }

    /// A manual seek is a discontinuous jump just like a skip — it restarts this track's decode
    /// chain from the new offset rather than trying to splice the running one, so it goes through
    /// the exact same `startPlayback` path.
    func seek(to time: TimeInterval) {
        guard currentItem != nil else { return }
        startPlayback(atQueueIndex: currentIndex, autoplay: isPlaying, resumeAt: time)
    }

    /// Starts (or restarts) playback at `index` from scratch: stops whatever the engine had queued,
    /// invalidates any in-flight decode work via `decodeGeneration`, resolves a local file for the
    /// item, and begins scheduling its PCM onto `playerNode`. Used for every *discontinuous* entry
    /// point (initial play, skip, seek, jump-to-track, restoring a saved session) — the ordinary
    /// track-to-track boundary never calls this; it's handled by `prepareNextTrack`'s gapless
    /// hand-off instead.
    private func startPlayback(atQueueIndex index: Int, autoplay: Bool, resumeAt: TimeInterval? = nil) {
        guard queue.indices.contains(index) else { return }
        let item = queue[index]

        stopReportingSession(finalPosition: currentTime)
        decodeGeneration += 1
        let generation = decodeGeneration
        nextDecodeSessionId += 1
        let session = nextDecodeSessionId
        activeDecodeSession = session
        pendingNextSession = nil
        pendingNextItem = nil
        trackStartFrames.removeAll()
        sessionStartOffsetFrames.removeAll()
        framesScheduledSoFar = 0
        playerNode.stop()

        currentTime = resumeAt ?? 0
        updateNowPlayingInfo()
        isLoadingTrack = autoplay

        Task {
            guard let fileURL = await self.ensureLocalFile(for: item) else {
                if index == self.currentIndex { self.isLoadingTrack = false }
                return
            }
            guard generation == self.decodeGeneration else { return }

            guard let feeder = try? TrackFeeder(fileURL: fileURL, outputFormat: self.canonicalFormat, seekSeconds: resumeAt ?? 0) else {
                if index == self.currentIndex { self.isLoadingTrack = false }
                return
            }
            guard generation == self.decodeGeneration else { return }

            self.sessionStartOffsetFrames[session] = AVAudioFramePosition((resumeAt ?? 0) * self.canonicalFormat.sampleRate)
            self.beginScheduling(feeder: feeder, session: session, generation: generation)

            if !self.engine.isRunning {
                try? self.engine.start()
            }
            if autoplay {
                self.playerNode.play()
                self.isPlaying = true
                self.startReportingSessionIfNeeded()
            }
            self.isLoadingTrack = false
        }

        cacheUpcomingTrack()
    }

    /// Reads one chunk from `feeder` and schedules it onto `playerNode` with no explicit time —
    /// which is exactly what makes this gapless: omitting a time schedules the buffer to play
    /// immediately following whatever was previously scheduled on this node, true regardless of
    /// which track that previous buffer belonged to. Each non-final chunk's completion handler
    /// (`.dataConsumed`, fired roughly in step with real playback) pulls in the next chunk of the
    /// *same* track; the final chunk instead waits for `.dataRendered` (fired once that audio has
    /// actually played) to flip bookkeeping over to the next track, and kicks off preparing it.
    private func scheduleChunk(feeder: TrackFeeder, session: Int, generation: Int, isFirstChunkOfTrack: Bool) {
        guard generation == decodeGeneration else { return }
        guard let chunk = feeder.readChunk(approximateSeconds: chunkDurationSeconds) else {
            // Pathological empty/corrupt file — nothing to schedule at all for this track, so just
            // advance past it immediately rather than leaving the queue stuck in silence forever.
            if session == activeDecodeSession {
                handleTrackFinishedRendering(session: session, generation: generation)
            }
            return
        }

        if isFirstChunkOfTrack {
            trackStartFrames[session] = framesScheduledSoFar - (sessionStartOffsetFrames[session] ?? 0)
        }
        framesScheduledSoFar += AVAudioFramePosition(chunk.frameLength)

        if feeder.isExhausted {
            playerNode.scheduleBuffer(chunk, completionCallbackType: .dataRendered) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleTrackFinishedRendering(session: session, generation: generation)
                }
            }
            prepareNextTrack(afterSession: session, generation: generation)
        } else {
            playerNode.scheduleBuffer(chunk, completionCallbackType: .dataConsumed) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleChunk(feeder: feeder, session: session, generation: generation, isFirstChunkOfTrack: false)
                }
            }
        }
    }

    /// Schedules a track's first chunk and then, synchronously and immediately (not waiting on any
    /// completion callback), tops up a few more right behind it — see `chunkDurationSeconds`/
    /// `targetBufferedChunks` above for why. Used for every point a track's decode chain begins:
    /// `startPlayback` and `prepareNextTrack`'s gapless hand-off alike.
    private func beginScheduling(feeder: TrackFeeder, session: Int, generation: Int) {
        scheduleChunk(feeder: feeder, session: session, generation: generation, isFirstChunkOfTrack: true)
        var buffered = 1
        while buffered < targetBufferedChunks, generation == decodeGeneration, !feeder.isExhausted {
            scheduleChunk(feeder: feeder, session: session, generation: generation, isFirstChunkOfTrack: false)
            buffered += 1
        }
    }

    /// Kicked off the moment the current track's *last* chunk is scheduled (not yet rendered) —
    /// resolves and decodes `queue[currentIndex + 1]` (read fresh here, so it reflects any queue
    /// mutation made since this track started) and, once ready, schedules its first chunk right
    /// after what's already queued. In the common case the file is already locally cached well
    /// ahead of time via `cacheUpcomingTrack()`, so this finishes long before the current track's
    /// remaining buffered audio actually runs out.
    private func prepareNextTrack(afterSession session: Int, generation: Int) {
        guard currentIndex + 1 < queue.count else { return }
        let nextItem = queue[currentIndex + 1]
        nextDecodeSessionId += 1
        let nextSession = nextDecodeSessionId

        Task {
            guard let fileURL = await self.ensureLocalFile(for: nextItem) else { return }
            guard generation == self.decodeGeneration else { return }

            guard let feeder = try? TrackFeeder(fileURL: fileURL, outputFormat: self.canonicalFormat) else { return }
            guard generation == self.decodeGeneration else { return }

            self.pendingNextSession = nextSession
            self.pendingNextItem = nextItem
            self.beginScheduling(feeder: feeder, session: nextSession, generation: generation)
        }
    }

    /// Fires once the just-finished track's last buffer has actually finished rendering (real
    /// playback time) — the moment to flip every piece of bookkeeping (index, subqueue, Jellyfin
    /// progress reporting, Now Playing info) over to the next track, matching what the engine
    /// already gaplessly moved on to at the audio level moments earlier.
    private func handleTrackFinishedRendering(session: Int, generation: Int) {
        guard generation == decodeGeneration, session == activeDecodeSession else { return }
        trackStartFrames.removeValue(forKey: session)
        sessionStartOffsetFrames.removeValue(forKey: session)

        guard currentIndex + 1 < queue.count else {
            handleReachedEndOfQueue()
            return
        }

        let finalPosition = currentTime
        stopReportingSession(finalPosition: finalPosition)
        if subqueueCount > 0 {
            subqueueCount -= 1
        }
        currentIndex += 1
        currentTime = 0
        updateNowPlayingInfo()
        cacheUpcomingTrack()

        if let pendingSession = pendingNextSession, pendingNextItem?.Id == currentItem?.Id {
            activeDecodeSession = pendingSession
        } else {
            // Not ready in time (slow network, or pre-caching disabled) — there was an audible gap
            // here, and nothing left scheduled to continue from, so start fresh against whatever is
            // now actually at `currentIndex`.
            startPlayback(atQueueIndex: currentIndex, autoplay: isPlaying)
        }
        pendingNextSession = nil
        pendingNextItem = nil

        if isPlaying {
            startReportingSessionIfNeeded()
        }
    }

    /// The very last song in the queue finished playing with nothing prepared after it — unlike every
    /// other track boundary, there's no next item for the player to fall through to, so this is the
    /// one case that needs its own "are we still actually playing" correction.
    private func handleReachedEndOfQueue() {
        isPlaying = false
        isLoadingTrack = false
        updateNowPlayingPlaybackState()
        stopReportingSession(finalPosition: currentTime)
        persistPlaybackState()
    }

    /// Always returns a *local* file — decoding via `AVAudioFile` for the gapless PCM pipeline needs
    /// random local file access, which a remote URL can't provide directly. A track that isn't
    /// downloaded or opportunistically cached yet is fetched in full here (the same
    /// `CacheManager.cacheTrack` used for background pre-caching, just awaited instead of fired and
    /// forgotten) before this returns — in practice this only means an actual wait for a track
    /// that's being played for the very first time with no lead time; anything already reached via
    /// `cacheUpcomingTrack()`'s lookahead resolves instantly from disk.
    private func ensureLocalFile(for item: BaseItemDto) async -> URL? {
        if let downloadedURL = await DownloadStore.shared.localFileURL(forItemId: item.Id) {
            return downloadedURL
        }
        if let cachedURL = await CacheManager.shared.localFileURL(forItemId: item.Id) {
            return cachedURL
        }
        let bitrate = StreamingQualitySettings.shared.currentStreamingBitrateKbps()
        guard let remoteURL = JellyfinAPIClient.shared.streamURL(itemId: item.Id, maxBitrateKbps: bitrate) else { return nil }
        await CacheManager.shared.cacheTrack(
            id: item.Id,
            title: item.Name,
            artistName: item.AlbumArtist ?? item.Artists?.first ?? "",
            albumName: item.Album ?? "",
            albumId: item.AlbumId,
            durationTicks: item.RunTimeTicks ?? 0,
            remoteURL: remoteURL
        )
        return await CacheManager.shared.localFileURL(forItemId: item.Id)
    }

    private func cacheUpcomingTrack() {
        let lookahead = CacheManager.preCacheLookahead
        guard lookahead > 0 else { return }

        let bitrate = StreamingQualitySettings.shared.currentStreamingBitrateKbps()
        for offset in 1...lookahead {
            guard queue.indices.contains(currentIndex + offset) else { break }
            let item = queue[currentIndex + offset]
            guard let remoteURL = JellyfinAPIClient.shared.streamURL(itemId: item.Id, maxBitrateKbps: bitrate) else { continue }
            cache(item, from: remoteURL)
        }
    }

    private func cache(_ item: BaseItemDto, from remoteURL: URL) {
        Task.detached(priority: .utility) {
            await CacheManager.shared.cacheTrack(
                id: item.Id,
                title: item.Name,
                artistName: item.AlbumArtist ?? item.Artists?.first ?? "",
                albumName: item.Album ?? "",
                albumId: item.AlbumId,
                durationTicks: item.RunTimeTicks ?? 0,
                remoteURL: remoteURL
            )
        }
    }

    private func ticks(from seconds: TimeInterval) -> Int64 {
        Int64(seconds * 10_000_000)
    }

    private func startReportingSessionIfNeeded() {
        guard let item = currentItem, activeReportingSession?.itemId != item.Id else { return }
        let sessionId = UUID().uuidString
        activeReportingSession = (item.Id, sessionId)
        lastProgressReportTime = currentTime
        let position = ticks(from: currentTime)
        Task.detached(priority: .utility) {
            await JellyfinAPIClient.shared.reportPlaybackStart(itemId: item.Id, playSessionId: sessionId, positionTicks: position)
        }
    }

    private func reportProgress(isPaused: Bool) {
        guard let session = activeReportingSession else { return }
        let position = ticks(from: currentTime)
        Task.detached(priority: .utility) {
            await JellyfinAPIClient.shared.reportPlaybackProgress(itemId: session.itemId, playSessionId: session.sessionId, positionTicks: position, isPaused: isPaused)
        }
    }

    private func stopReportingSession(finalPosition: TimeInterval) {
        guard let session = activeReportingSession else { return }
        activeReportingSession = nil
        let position = ticks(from: finalPosition)
        Task.detached(priority: .utility) {
            await JellyfinAPIClient.shared.reportPlaybackStopped(itemId: session.itemId, playSessionId: session.sessionId, positionTicks: position)
        }
    }

    private func configureAudioSession() {
        #if canImport(UIKit)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
        #endif
    }

    private func configureRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        // A single-button headphone remote (most wired headsets, and some Bluetooth ones) sends
        // this instead of a separate play/pause command for its one button — without a target here,
        // that button press has nowhere to go and silently does nothing.
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.skipToNext()
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.skipToPrevious()
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: event.positionTime)
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let item = currentItem else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        let info: [String: Any] = [
            MPMediaItemPropertyTitle: item.Name,
            MPMediaItemPropertyArtist: item.AlbumArtist ?? item.Artists?.first ?? "",
            MPMediaItemPropertyAlbumTitle: item.Album ?? "",
            MPMediaItemPropertyPlaybackDuration: Double(item.RunTimeTicks ?? 0) / 10_000_000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtwork(for: item)
    }

    private func updateNowPlayingElapsedTime() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlaybackState() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for item: BaseItemDto) {
        #if canImport(UIKit)
        let itemId = item.artworkItemId

        Task {
            await ImageCache.shared.fetchAndStore(itemId: itemId)
            guard let data = await ImageCache.shared.data(itemId: itemId, imageType: "Primary"),
                  let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            guard var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo,
                  currentInfo[MPMediaItemPropertyTitle] as? String == item.Name else { return }
            currentInfo[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
        }
        #endif
    }
}
