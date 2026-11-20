//
//  CarPlayContent.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 11/14/26.
//

#if canImport(CarPlay)
import CarPlay
import ImageIO
import UIKit

/// Builds the CarPlay template tree — the root list ("Playlists", "Recently Added") and the song
/// lists pushed from it — and wires each row's handler to the exact same playback entry point the
/// phone UI uses (`AudioPlayerManager.shared.play(queue:startAt:)`), so queueing/caching/now-playing
/// behave identically whether a song was tapped on the phone or on the car's screen.
///
/// Every handler explicitly hops to the main actor before touching `interfaceController` or
/// `AudioPlayerManager` — `CPListItem.handler`'s closure type is CarPlay's own, not guaranteed to
/// run on the main actor by this module's default isolation, the same reasoning
/// `AudioPlayerManager.observeRouteChanges()` already applies to `NotificationCenter`'s callback.
enum CarPlayContent {
    static func buildRootTemplate(interfaceController: CPInterfaceController) async -> CPListTemplate {
        async let playlists = playlistsSection(interfaceController: interfaceController)
        async let recentlyAdded = recentlyAddedSection(interfaceController: interfaceController)
        let sections = await [playlists, recentlyAdded]
        return CPListTemplate(title: "Bluefin", sections: sections)
    }

    private static func playlistsSection(interfaceController: CPInterfaceController) async -> CPListSection {
        guard let playlists = await LibraryCache.shared.items(for: "playlists") else {
            return CPListSection(items: [notSyncedItem()], header: "Playlists", sectionIndexTitle: nil)
        }
        guard !playlists.isEmpty else {
            return CPListSection(items: [emptyItem("No playlists yet")], header: "Playlists", sectionIndexTitle: nil)
        }

        var items: [CPListItem] = []
        for playlist in playlists {
            let item = CPListItem(text: playlist.Name, detailText: nil)
            item.handler = { [weak interfaceController] _, completion in
                completion()
                Task {
                    let songs = await LibraryCache.shared.items(for: "playlistSongs:\(playlist.Id)") ?? []
                    await MainActor.run {
                        guard let interfaceController else { return }
                        let template = songListTemplate(
                            title: playlist.Name, songs: songs, interfaceController: interfaceController)
                        interfaceController.pushTemplate(template, animated: true, completion: nil)
                    }
                }
            }
            items.append(item)
            loadArtwork(for: playlist.Id, into: item)
        }
        return CPListSection(items: items, header: "Playlists", sectionIndexTitle: nil)
    }

    private static func recentlyAddedSection(interfaceController: CPInterfaceController) async -> CPListSection {
        guard let libraryId = JellyfinAPIClient.shared.selectedLibraryId,
            let albums = await LibraryCache.shared.items(for: "albums:\(libraryId)")
        else {
            return CPListSection(items: [notSyncedItem()], header: "Recently Added", sectionIndexTitle: nil)
        }
        guard !albums.isEmpty else {
            return CPListSection(items: [emptyItem("No albums yet")], header: "Recently Added", sectionIndexTitle: nil)
        }

        let recent = albums
            .sorted { ($0.dateCreated ?? .distantPast) > ($1.dateCreated ?? .distantPast) }
            .prefix(20)

        var items: [CPListItem] = []
        for album in recent {
            let item = CPListItem(text: album.Name, detailText: album.AlbumArtist)
            item.handler = { [weak interfaceController] _, completion in
                completion()
                Task {
                    let songs = await LibraryCache.shared.items(for: "albumSongs:\(album.Id)") ?? []
                    await MainActor.run {
                        guard let interfaceController else { return }
                        let template = songListTemplate(
                            title: album.Name, songs: songs, interfaceController: interfaceController)
                        interfaceController.pushTemplate(template, animated: true, completion: nil)
                    }
                }
            }
            items.append(item)
            loadArtwork(for: album.Id, into: item)
        }
        return CPListSection(items: items, header: "Recently Added", sectionIndexTitle: nil)
    }

    /// A playlist's or album's songs, with a leading "Shuffle" row above the plain song list —
    /// mirroring `PlayShuffleBar` on the phone.
    private static func songListTemplate(
        title: String, songs: [BaseItemDto], interfaceController: CPInterfaceController
    ) -> CPListTemplate {
        guard !songs.isEmpty else {
            return CPListTemplate(title: title, sections: [CPListSection(items: [emptyItem("No songs")])])
        }

        let shuffleItem = CPListItem(text: "Shuffle", detailText: nil, image: UIImage(systemName: "shuffle"))
        shuffleItem.handler = { [weak interfaceController] _, completion in
            completion()
            Task { @MainActor in
                AudioPlayerManager.shared.play(queue: songs.shuffled(), startAt: 0)
                interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
            }
        }

        var songItems: [CPListItem] = []
        for (index, song) in songs.enumerated() {
            let item = CPListItem(text: song.Name, detailText: song.AlbumArtist ?? song.Artists?.first)
            item.handler = { [weak interfaceController] _, completion in
                completion()
                Task { @MainActor in
                    AudioPlayerManager.shared.play(queue: songs, startAt: index)
                    interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
                }
            }
            songItems.append(item)
            loadArtwork(for: song.artworkItemId, into: item)
        }

        return CPListTemplate(
            title: title,
            sections: [
                CPListSection(items: [shuffleItem]),
                CPListSection(items: songItems, header: "Songs", sectionIndexTitle: nil),
            ]
        )
    }

    /// Fetches artwork off the main actor and assigns it once ready — `CPListItem.setImage` updates
    /// an already-displayed row live, so the list doesn't need to wait on every image before showing.
    private static func loadArtwork(for itemId: String, into item: CPListItem) {
        Task {
            if let image = await artworkImage(forItemId: itemId) {
                await MainActor.run { item.setImage(image) }
            }
        }
    }

    private static func artworkImage(forItemId id: String) async -> UIImage? {
        if let data = await ImageCache.shared.data(itemId: id, imageType: "Primary") {
            return thumbnail(from: data)
        }
        await ImageCache.shared.fetchAndStore(itemId: id)
        guard let data = await ImageCache.shared.data(itemId: id, imageType: "Primary") else { return nil }
        return thumbnail(from: data)
    }

    /// Jellyfin's "Primary" images are full-resolution cover art (often 1000px+). CPListItem.image
    /// is shown at roughly 60pt, and handing CarPlay.app a raw full-size `UIImage(data:)` over XPC
    /// crashed CarPlay's own iconservices placeholder-generation path on every launch. Decoding
    /// straight to a small thumbnail via ImageIO — rather than fully decoding the source and resizing
    /// after — avoids ever materializing the oversized image at all.
    private static func thumbnail(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 180,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private static func notSyncedItem() -> CPListItem {
        CPListItem(text: "Sync your library on your phone first", detailText: nil)
    }

    private static func emptyItem(_ text: String) -> CPListItem {
        CPListItem(text: text, detailText: nil)
    }
}
#endif
