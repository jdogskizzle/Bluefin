//
//  BaseItemDto.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Foundation

struct ItemsResponse: Codable {
    let Items: [BaseItemDto]
    let TotalRecordCount: Int
}

struct BaseItemDto: Codable, Identifiable, Hashable {
    let Id: String
    let Name: String
    let ItemType: String
    let CollectionType: String?
    let AlbumArtist: String?
    let Artists: [String]?
    let Album: String?
    let AlbumId: String?
    let ProductionYear: Int?
    let RunTimeTicks: Int64?
    let IndexNumber: Int?
    let ChildCount: Int?
    let ImageTags: [String: String]?
    /// Only present when fetched as part of a playlist's items — identifies this specific entry
    /// within that playlist (distinct from `Id`, the underlying song's own item id), since Jellyfin
    /// allows the same song to appear in a playlist more than once. Needed to remove the correct
    /// occurrence rather than just "a" copy of the song.
    let PlaylistItemId: String?
    /// ISO 8601 date-time string; only present when explicitly requested via `Fields=PremiereDate`
    /// (Jellyfin omits it by default). `ProductionYear` alone isn't precise enough to sort albums
    /// released in the same year correctly — see `premiereDate` for the parsed value.
    let PremiereDate: String?
    /// ISO 8601 date-time string of when this item was added to the Jellyfin library — only present
    /// when explicitly requested via `Fields=DateCreated`. Shown as "Date Added" in a song's details.
    let DateCreated: String?
    /// Only present when explicitly requested via `Fields=MediaSources` — carries the technical
    /// audio details (codec/bitrate/sample rate) shown in a song's details.
    let MediaSources: [MediaSourceInfo]?
    /// Only present when explicitly requested via `Fields=UserData` — carries this user's
    /// favorite/played state for the item.
    let UserData: UserDataDto?
    /// Only present when explicitly requested via `Fields=Genres` — an album's genre names, used
    /// to group albums by genre locally during sync rather than issuing one request per genre.
    let Genres: [String]?

    var id: String { Id }

    enum CodingKeys: String, CodingKey {
        case Id, Name, CollectionType, AlbumArtist, Artists, Album, AlbumId, ProductionYear, RunTimeTicks, IndexNumber, ChildCount, ImageTags, PlaylistItemId, PremiereDate, DateCreated, MediaSources, UserData, Genres
        case ItemType = "Type"
    }
}

struct UserDataDto: Codable, Hashable {
    let IsFavorite: Bool?
}

struct MediaSourceInfo: Codable, Hashable {
    let Container: String?
    let MediaStreams: [MediaStreamInfo]?
}

struct MediaStreamInfo: Codable, Hashable {
    let StreamType: String?
    let Codec: String?
    let BitRate: Int?
    let SampleRate: Int?

    enum CodingKeys: String, CodingKey {
        case StreamType = "Type"
        case Codec, BitRate, SampleRate
    }
}

extension BaseItemDto {
    var formattedDuration: String? {
        guard let ticks = RunTimeTicks else { return nil }
        let totalSeconds = Int(ticks / 10_000_000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// The item id to request artwork for — songs have no art of their own, so this
    /// resolves to their album's art instead.
    var artworkItemId: String {
        if ItemType == "Audio", let albumId = AlbumId {
            return albumId
        }
        return Id
    }

    /// Parsed `PremiereDate`, for precise release-date sorting (two albums released in the same
    /// year still sort correctly relative to each other) — `nil` if the field wasn't requested/
    /// returned, or isn't in the format Jellyfin normally sends (fractional-second ISO 8601 UTC).
    var premiereDate: Date? {
        guard let PremiereDate else { return nil }
        if let date = Self.premiereDateFormatterWithFractionalSeconds.date(from: PremiereDate) {
            return date
        }
        return Self.premiereDateFormatter.date(from: PremiereDate)
    }

    private static let premiereDateFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let premiereDateFormatter = ISO8601DateFormatter()

    /// Parsed `DateCreated` — when this item was added to the Jellyfin library.
    var dateCreated: Date? {
        guard let DateCreated else { return nil }
        if let date = Self.premiereDateFormatterWithFractionalSeconds.date(from: DateCreated) {
            return date
        }
        return Self.premiereDateFormatter.date(from: DateCreated)
    }

    /// The first audio stream of the first media source — a song has exactly one of each in
    /// practice, so there's no need to pick among multiple.
    var primaryAudioStream: MediaStreamInfo? {
        MediaSources?.first?.MediaStreams?.first { $0.StreamType == "Audio" }
    }

    /// A copy with a different `ChildCount` — used to keep a playlist's own cached record (its
    /// track count) in step immediately after adding/removing a song, without waiting for the next
    /// full library sync to refetch it from the server.
    func withChildCount(_ newChildCount: Int) -> BaseItemDto {
        BaseItemDto(
            Id: Id, Name: Name, ItemType: ItemType, CollectionType: CollectionType,
            AlbumArtist: AlbumArtist, Artists: Artists, Album: Album, AlbumId: AlbumId,
            ProductionYear: ProductionYear, RunTimeTicks: RunTimeTicks, IndexNumber: IndexNumber,
            ChildCount: newChildCount, ImageTags: ImageTags, PlaylistItemId: PlaylistItemId,
            PremiereDate: PremiereDate, DateCreated: DateCreated, MediaSources: MediaSources, UserData: UserData,
            Genres: Genres
        )
    }
}
