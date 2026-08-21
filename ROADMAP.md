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
- [ ] Background audio session caching layer — no `AVAssetResourceLoaderDelegate`, no disk caching of streamed audio yet. Playback currently streams directly with no cache-ahead.
- [ ] Pre-caching of upcoming tracks/album — not implemented.

## Phase 3: Main UI Architecture — partially done
- [x] Tab navigation shell (`Main/MainTabView.swift`): Home, Library, Search, Settings
- [x] Library view: Artists, Albums (grid), Playlists, Album detail, Playlist detail, numbered song rows, play/shuffle bar
- [x] Search view (`Search/SearchView.swift`, `SearchViewModel.swift`)
- [x] Settings: music library selector, server info, sign out
- [ ] Home view — currently just a placeholder ("Welcome to Bluefin"). Needs: pinned playlists, recently played, random suggestions, "Listen List"
- [ ] Settings: stream quality selector, cache limit controls, equalizer toggles — none exist yet

## Phase 4: Advanced UX & Gestures — mostly not started
- [x] Expandable large player (`Player/NowPlayingView.swift`), mini-player (`Player/MiniPlayerView.swift`)
- [x] Queue view (`Player/QueueView.swift`)
- [x] Synced lyrics view (`Player/LyricsView.swift`)
- [ ] Swipe-to-queue / swipe-to-playlist gestures on list rows — not implemented (the `DragGesture` in `ArtistListView.swift` is just a tap/press effect, not a queue/playlist swipe action)
- [ ] Manual queue reordering (drag-to-reorder in `QueueView`) — not implemented
- [ ] Configurable swipe behavior in Settings — not implemented

## Phase 5: Equalizer & Offline Engine — not started
- [ ] Custom EQ (`AVAudioUnitEQ`) in the playback pipeline
- [ ] Track downloading for offline playlists
- [ ] Offline fallback (local SwiftData + downloaded files when no connectivity)
- [ ] Cache size limit + LRU eviction

## Not in original plan, worth deciding on
- [ ] WebSocket sync for real-time playback reporting (progress/play count back to Jellyfin) — API client currently has no WebSocket usage
- [ ] "Listen List" persistence (needs SwiftData model above)

---

## Suggested near-term priorities
1. **SwiftData models** (`CachedTrack`, `ListeningListAlbum`, session storage) — this unblocks Home view content, offline mode, and downloads; everything else in Phase 5 depends on it.
2. **Home view** — biggest visible gap; currently a placeholder despite Library/Player being fairly built out.
3. **Audio caching / pre-caching** — needed before offline or download features make sense.
4. **Queue drag-to-reorder** — small, high-value polish on an already-built `QueueView`.
