# Bluefin Feature Checklist

Status as of 2026-08-20, verified against the current codebase (not just prior planning notes).

---

## Phase 1: Foundation & Authentication — mostly done
- [x] Project structure (`Core/`, `Features/`, split into Audio, Network, Storage, Library, Main, Onboarding, Player, Search, Settings)
- [x] Server connection + login flow (`Onboarding/LoginView.swift`, `LoginViewModel.swift`)
- [x] Keychain-backed credential storage (`Core/Storage/KeychainHelper.swift`)
- [x] API client for libraries, artists, albums, playlists (`Core/Network/JellyfinAPIClient.swift`)
- [x] SwiftData persistence layer: `CachedTrack` and `ListeningListAlbum` models (`Core/Storage/CachedTrack.swift`, `Core/Storage/ListeningListAlbum.swift`), registered in `BluefinApp`'s `ModelContainer`. No `JellyfinServer` model — server credentials stay in Keychain via `JellyfinAPIClient`/`KeychainHelper`, which is already the more secure fit for a token. Removed the unused Xcode-template `Item.swift`/`ContentView.swift`.

## Phase 2: Core Audio Playback Engine — partially done
- [x] `AudioPlayerManager` singleton on `AVQueuePlayer` (`Core/Audio/AudioPlayerManager.swift`)
- [x] Lock screen / Control Center integration (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`)
- [x] AirPlay / route picker (`Player/RoutePickerView.swift`), volume slider (`Player/VolumeSliderView.swift`)
- [x] Background disk caching (`Core/Storage/CacheManager.swift`, a `@ModelActor` backed by `CachedTrack`): plays from a cached local file when present, otherwise streams directly and downloads the file in the background for next time. Uses whole-file background download rather than an `AVAssetResourceLoaderDelegate` byte-stream intercept — simpler and more robust, at the cost of ~2x bandwidth on an uncached track's first play (streamed for immediate playback + downloaded for the cache in parallel). Worth revisiting with a resource-loader delegate later if that bandwidth cost matters.
- [x] Pre-caching upcoming queue tracks — `AudioPlayerManager` kicks off background cache downloads for the next N queue items whenever the current track loads; N is `CacheManager.preCacheLookahead`, configurable in Settings (default 10).

## Phase 3: Main UI Architecture — partially done
- [x] Tab navigation shell (`Main/MainTabView.swift`): Home, Library, Search, Settings
- [x] Library view: Artists, Albums (grid), Playlists, Album detail, Playlist detail, numbered song rows, play/shuffle bar
- [x] Search view (`Search/SearchView.swift`, `SearchViewModel.swift`)
- [x] Settings: music library selector, server info, sign out
- [ ] Home view — currently just a placeholder ("Welcome to Bluefin"). Needs: pinned playlists, recently played, random suggestions, "Listen List"
- [x] Settings: cache limit controls (`Storage` section — usage display, 5/10/15/20 GB size limit picker, 1/2/3/5-track pre-cache lookahead picker, Clear Cache)
- [ ] Settings: stream quality selector, equalizer toggles — none exist yet

## Phase 4: Advanced UX & Gestures — mostly not started
- [x] Expandable large player (`Player/NowPlayingView.swift`), mini-player (`Player/MiniPlayerView.swift`)
- [x] Queue view (`Player/QueueView.swift`)
- [x] Synced lyrics view (`Player/LyricsView.swift`)
- [ ] Swipe-to-queue / swipe-to-playlist gestures on list rows — not implemented (the `DragGesture` in `ArtistListView.swift` is just a tap/press effect, not a queue/playlist swipe action)
- [ ] Manual queue reordering (drag-to-reorder in `QueueView`) — not implemented
- [ ] Configurable swipe behavior in Settings — not implemented

## Phase 5: Equalizer & Offline Engine — not started
- [ ] Custom EQ (`AVAudioUnitEQ`) in the playback pipeline
- [ ] Explicit "download for offline" on playlists/albums (distinct from the passive play-time cache above — this would eagerly download a whole playlist regardless of play history)
- [ ] Offline fallback (local SwiftData + downloaded files when no connectivity) — `CacheManager` gives playback a local-file path when cached, but nothing yet detects offline state or falls back to cached-only browsing when Library/Search calls fail
- [x] Cache size limit + LRU eviction (`CacheManager.evictIfOverLimit`, oldest-`lastAccessedDate`-first, limit configurable in Settings)

## Later
- [ ] WebSocket sync for real-time playback reporting (progress/play count back to Jellyfin) — API client currently has no WebSocket usage
- [ ] "Listen List" persistence (needs SwiftData model above)
