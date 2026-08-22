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

    private let player = AVPlayer()
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?

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
        configureRemoteCommandCenter()
        addPeriodicTimeObserver()
        observeAppBackgrounding()
        restorePlaybackState()
    }

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
        loadCurrentItem(autoplay: false, resumeAt: state.currentTime)
    }

    func play(queue newQueue: [BaseItemDto], startAt index: Int) {
        guard newQueue.indices.contains(index) else { return }
        replaceQueue(newQueue)
        currentIndex = index
        subqueueCount = 0
        loadCurrentItem(autoplay: true)
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
        loadCurrentItem(autoplay: true)
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
        player.pause()
        isPlaying = false
        updateNowPlayingPlaybackState()
        persistPlaybackState()
        reportProgress(isPaused: true)
    }

    func resume() {
        player.play()
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
        loadCurrentItem(autoplay: isPlaying)
    }

    func skipToPrevious() {
        if currentTime > 3 || currentIndex == 0 {
            seek(to: 0)
            return
        }
        currentIndex -= 1
        loadCurrentItem(autoplay: isPlaying)
    }

    func seek(to time: TimeInterval) {
        // A small tolerance lets AVPlayer land on the nearest convenient keyframe instead of doing a
        // fully precise decode — lyric lines are seconds apart, so this is imperceptibly close while
        // avoiding the audible restart gap a zero-tolerance seek introduces.
        let tolerance = CMTime(seconds: 0.2, preferredTimescale: 1000)
        player.seek(to: CMTime(seconds: time, preferredTimescale: 1000), toleranceBefore: tolerance, toleranceAfter: tolerance)
        currentTime = time
        updateNowPlayingElapsedTime()
        reportProgress(isPaused: !isPlaying)
    }

    private func loadCurrentItem(autoplay: Bool, resumeAt: TimeInterval? = nil) {
        guard let item = currentItem else { return }
        // Whatever was previously loaded (if its session ever actually started) is done as of this
        // switch — reported here, before `currentTime` is reset below, so the stop position reflects
        // where that item was actually left rather than the new item's starting position.
        stopReportingSession(finalPosition: currentTime)
        removeEndObserver()
        currentTime = resumeAt ?? 0
        updateNowPlayingInfo()

        Task {
            guard let url = await playbackURL(for: item) else { return }
            // The user may have skipped again while this awaited — don't clobber newer state.
            guard item.Id == self.currentItem?.Id else { return }

            let asset = AVURLAsset(url: url)
            let playerItem = AVPlayerItem(asset: asset)
            playerItem.audioMix = await EqualizerAudioMixFactory.makeAudioMix(for: asset)
            guard item.Id == self.currentItem?.Id else { return }
            self.player.replaceCurrentItem(with: playerItem)
            self.addEndObserver(for: playerItem)

            if let resumeAt {
                self.seek(to: resumeAt)
            }

            if autoplay {
                self.player.play()
                self.isPlaying = true
                self.startReportingSessionIfNeeded()
            }
        }

        cacheUpcomingTrack()
    }

    /// Local cached file if present, otherwise the remote stream URL — kicking off a background
    /// download to cache it for next time. A real download (see `DownloadStore`) always wins over
    /// the opportunistic cache when both exist — it's the copy the user explicitly asked to keep.
    private func playbackURL(for item: BaseItemDto) async -> URL? {
        if let downloadedURL = await DownloadStore.shared.localFileURL(forItemId: item.Id) {
            return downloadedURL
        }
        if let localURL = await CacheManager.shared.localFileURL(forItemId: item.Id) {
            return localURL
        }
        let bitrate = StreamingQualitySettings.shared.currentStreamingBitrateKbps()
        guard let remoteURL = JellyfinAPIClient.shared.streamURL(itemId: item.Id, maxBitrateKbps: bitrate) else { return nil }
        cache(item, from: remoteURL)
        return remoteURL
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

    private func addEndObserver(for item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.skipToNext()
            }
        }
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = time.seconds
                if self.isPlaying, self.currentTime - self.lastProgressReportTime >= self.progressReportInterval {
                    self.lastProgressReportTime = self.currentTime
                    self.reportProgress(isPaused: false)
                }
            }
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
