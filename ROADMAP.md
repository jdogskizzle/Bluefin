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
- [x] Artwork caching (`Core/Storage/ImageCache.swift`, plain disk cache keyed by item id + image type + width) and lyrics caching (`CacheManager.lyrics(for:)`, persisted as JSON on `CachedTrack.lyricsData`, including caching an empty result so a track confirmed to have no lyrics isn't re-fetched). All 9 `AsyncImage` call sites and the lock-screen artwork fetch now go through a shared `CachedAsyncImage` view / `ImageCache`; both lyrics call sites (`LyricsView`, `NowPlayingView`) go through `CacheManager.lyrics(for:)`.

## Phase 3: Main UI Architecture — partially done
- [x] Tab navigation shell (`Main/MainTabView.swift`): Home, Library, Search, Settings
- [x] Library view: Artists, Albums (grid), Playlists, Album detail, Playlist detail, numbered song rows, play/shuffle bar
- [x] Search view (`Search/SearchView.swift`, `SearchViewModel.swift`)
- [x] Settings: music library selector, server info, sign out
- [ ] Home view — currently just a placeholder ("Welcome to Bluefin"). Needs: pinned playlists, recently played, random suggestions, "Listen List"
- [x] Settings: cache limit controls (`Storage` section — usage display, 1/2/5/10 GB size limit picker, 5/10/15/20-track pre-cache lookahead picker, Clear Cache)
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
- [x] Offline library browsing, now via an explicit blocking sync rather than opportunistic background caching (superseding an earlier opportunistic-caching version of this same line). `Core/Storage/LibraryCache.swift` (+ `CachedItemList`) persists the result of every library query; `LibraryListViewModel` is now a pure cache reader with no network fallback of its own — every list screen (Artists, Albums, Songs, Playlists, an artist's albums, an album's/playlist's songs) shows only what a sync has put there, or a "Not Synced Yet" prompt pointing at Settings. `Core/Storage/LibrarySyncManager.swift` is the *only* thing that talks to Jellyfin for library content: a Settings → "Sync Library" button opens a blocking sheet (`Features/Settings/LibrarySyncView.swift`) with a "Sync Now" button and a combined progress bar across 8 steps (artists, albums, songs, playlists, playlist songs, artist albums, artwork, lyrics), non-dismissable while running. Lyrics were an initial gap in this rework — they'd been left on the old opportunistic per-track path (fetched only when a track's Lyrics view was actually opened) rather than folded into the sync; fixed by adding a Lyrics step that calls the existing `CacheManager.lyrics(for:)` (which already checks its own cache first) across every synced song. Album-song lists are derived locally from one whole-library song fetch (grouped by album, sorted by track number) rather than one network call per album; playlist-song lists and per-artist album lists can't be derived that way (Jellyfin doesn't expose playlist membership or artist-id linkage on a plain record) so those go out as bounded-concurrency requests (6 at a time), with per-item failures skipped rather than aborting the whole sync. `ImageCache` was reworked to key by item id + image type only (one canonical width per type, not whatever width the current screen happens to want), so a sync-cached image is a guaranteed hit everywhere it's displayed; sync eagerly caches Primary art for every artist/album/playlist plus Backdrop for artists. `CachedAsyncImage` keeps a live network fallback (unlike the list data) so an unsynced now-playing track still shows artwork in the mini-player/Now Playing/lock screen — that's the one place caching stays opportunistic, since going without playback artwork for anything not yet synced seemed like a worse tradeoff than the consistency of "sync is the only path in." The Settings library *picker* (which Jellyfin views exist to choose from) still auto-refreshes on its own — it's a bootstrapping concern (you need it to pick a library before syncing that library), not "library content." Search stays live/online-only.
- [x] Cache size limit + LRU eviction (`CacheManager.evictIfOverLimit`, oldest-`lastAccessedDate`-first, limit configurable in Settings)

## Later
- [ ] WebSocket sync for real-time playback reporting (progress/play count back to Jellyfin) — API client currently has no WebSocket usage
- [ ] "Listen List" persistence (needs SwiftData model above)
