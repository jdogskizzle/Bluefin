//
//  Item.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
