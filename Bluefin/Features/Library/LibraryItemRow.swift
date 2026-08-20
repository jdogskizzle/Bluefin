//
//  LibraryItemRow.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import SwiftUI

struct LibraryItemRow: View {
    let item: BaseItemDto

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var artwork: some View {
        let url = JellyfinAPIClient.shared.imageURL(itemId: artworkItemId, maxWidth: 100)
        Group {
            switch item.ItemType {
            case "MusicArtist":
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "music.mic")
                        .foregroundStyle(.secondary)
                }
                .clipShape(Circle())
            default:
                AsyncImage(url: url) { image in
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

    private var artworkItemId: String {
        if item.ItemType == "Audio", let albumId = item.AlbumId {
            return albumId
        }
        return item.Id
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

    private var title: String {
        if item.ItemType == "Audio" {
            let track = item.IndexNumber.map(String.init) ?? "–"
            return "\(track). \(item.Name)"
        }
        return item.Name
    }

    private var subtitle: String? {
        switch item.ItemType {
        case "MusicAlbum":
            let parts = [item.AlbumArtist, item.ProductionYear.map(String.init)].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case "Audio":
            return formattedDuration(ticks: item.RunTimeTicks)
        case "Playlist":
            return "\(item.ChildCount ?? 0) songs"
        default:
            return nil
        }
    }

    private func formattedDuration(ticks: Int64?) -> String? {
        guard let ticks else { return nil }
        let totalSeconds = Int(ticks / 10_000_000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
