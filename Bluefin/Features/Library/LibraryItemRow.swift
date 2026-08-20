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
                Text(item.Name)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var artwork: some View {
        let url = JellyfinAPIClient.shared.imageURL(itemId: item.artworkItemId, maxWidth: 100)
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
            return item.formattedDuration
        case "Playlist":
            return "\(item.ChildCount ?? 0) songs"
        default:
            return nil
        }
    }
}
