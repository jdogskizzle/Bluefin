//
//  LibraryItemRow.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import SwiftUI

struct LibraryItemRow: View {
    let item: BaseItemDto
    var isPinned: Bool = false
    @ObservedObject private var player = AudioPlayerManager.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var pinnedStore = PinnedPlaylistStore.shared

    private var isNowPlaying: Bool {
        item.ItemType == "Audio" && player.currentItem?.Id == item.Id
    }

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(item.Name)
                    .font(.body)
                    .foregroundStyle(isNowPlaying ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isNowPlaying ? Color.accentColor : Color.secondary)
                        .lineLimit(1)
                }
            }
            if hasTrailingContent {
                Spacer()
                trailingContent
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var hasTrailingContent: Bool {
        isPinned || item.ItemType == "Audio"
    }

    @ViewBuilder
    private var trailingContent: some View {
        HStack(spacing: 6) {
            if item.ItemType == "Audio" {
                if pinnedStore.isSongPinned(item.Id) {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                downloadIcon
                if let duration = item.formattedDuration {
                    Text(duration)
                        .font(.footnote)
                        .foregroundStyle(isNowPlaying ? Color.accentColor : Color.secondary)
                }
            }
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var downloadIcon: some View {
        switch downloadManager.state(for: item.Id) {
        case .notDownloaded:
            EmptyView()
        case .downloading:
            ProgressView()
                .controlSize(.mini)
        case .downloaded:
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            switch item.ItemType {
            case "MusicArtist":
                CachedAsyncImage(itemId: item.artworkItemId) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "music.mic")
                        .foregroundStyle(.secondary)
                }
                .clipShape(Circle())
            default:
                CachedAsyncImage(itemId: item.artworkItemId) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: fallbackSymbol)
                        .foregroundStyle(.secondary)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .frame(width: 44, height: 44)
    }

    private var fallbackSymbol: String {
        switch item.ItemType {
        case "MusicArtist": return "music.mic"
        case "MusicAlbum": return "square.stack"
        case "Audio": return "music.note"
        case "Playlist": return "music.note.list"
        default: return "questionmark"
        }
    }

    private var subtitle: String? {
        switch item.ItemType {
        case "MusicAlbum":
            let parts = [item.AlbumArtist, item.ProductionYear.map(String.init)].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case "Audio":
            return nil
        case "Playlist":
            return "\(item.ChildCount ?? 0) songs"
        default:
            return nil
        }
    }
}
