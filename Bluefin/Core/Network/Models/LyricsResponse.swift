//
//  LyricsResponse.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Foundation

struct LyricsResponse: Codable {
    let Lyrics: [LyricLine]
}

struct LyricLine: Codable {
    let Text: String
    let Start: Int64?

    /// Timestamp this line starts at, in seconds — nil for unsynced lyrics.
    var startSeconds: TimeInterval? {
        guard let start = Start else { return nil }
        return TimeInterval(start) / 10_000_000
    }
}
