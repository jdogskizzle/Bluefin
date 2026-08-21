//
//  LibraryCacheChangeCenter.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/20/26.
//

import Combine

/// Broadcasts which `LibraryCache` key just changed, so a `LibraryListViewModel` already on screen
/// and watching that same key can refresh immediately — e.g. removing a song from a playlist you're
/// currently viewing — instead of only picking up the change the next time that screen appears.
enum LibraryCacheChangeCenter {
    static let didChange = PassthroughSubject<String, Never>()
}
