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

    @Published private(set) var queue: [BaseItemDto] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0

    var currentItem: BaseItemDto? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }

    private let player = AVPlayer()
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?

    private override init() {
        super.init()
        configureAudioSession()
        configureRemoteCommandCenter()
        addPeriodicTimeObserver()
    }

    func play(queue newQueue: [BaseItemDto], startAt index: Int) {
        guard newQueue.indices.contains(index) else { return }
        queue = newQueue
        currentIndex = index
        loadCurrentItem(autoplay: true)
    }

    /// Jumps to a track already in the current queue, leaving the rest of the queue unchanged.
    func play(at index: Int) {
        guard queue.indices.contains(index), index != currentIndex else { return }
        currentIndex = index
        loadCurrentItem(autoplay: true)
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingPlaybackState()
    }

    func resume() {
        player.play()
        isPlaying = true
        updateNowPlayingPlaybackState()
    }

    func skipToNext() {
        guard currentIndex + 1 < queue.count else { return }
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
    }

    private func loadCurrentItem(autoplay: Bool) {
        guard let item = currentItem, let url = JellyfinAPIClient.shared.streamURL(itemId: item.Id) else { return }
        removeEndObserver()

        let playerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)
        currentTime = 0
        addEndObserver(for: playerItem)
        updateNowPlayingInfo()

        if autoplay {
            player.play()
            isPlaying = true
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
                self?.currentTime = time.seconds
            }
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
        guard let url = JellyfinAPIClient.shared.imageURL(itemId: item.artworkItemId, maxWidth: 600) else { return }

        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            guard var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo,
                  currentInfo[MPMediaItemPropertyTitle] as? String == item.Name else { return }
            currentInfo[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
        }
        #endif
    }
}
