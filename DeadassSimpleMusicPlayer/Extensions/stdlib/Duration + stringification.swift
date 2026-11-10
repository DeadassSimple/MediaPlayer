//
//  Duration + stringification.swift
//  DeadassSimpleMusicPlayer
//
//  Created by Ky on 2026-11-09.
//

import Foundation



public extension Duration {
    /// Formats the current duration as a position in a media track, such as `0:04`, `1:23`, `54:32`, `1:23:45`, etc.
    var mediaPositionTimestamp: String {
        "\(Int(timeInterval / 60)):\(Int(timeInterval.truncatingRemainder(dividingBy: 60)).formatted(.number.precision(.integerLength(2))))"
    }
}
