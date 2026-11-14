//
//  Duration + stringification.swift
//  DeadassSimpleMusicPlayer
//
//  Created by Ky on 2026-11-09.
//

import Foundation



public extension Duration {
    /// Formats the current duration as a position in a media item, such as `0:04`, `1:23`, `54:32`, `1:23:45`, etc.
    var mediaPositionTimestamp: String {
        let wholeSeconds = components.seconds
        let hours = wholeSeconds / (60 * 60)
        let minutes = (wholeSeconds / 60) % 60
        let seconds = wholeSeconds % 60
        
        if 0 < hours {
            return "\(hours):\(minutes.formatted(.number.precision(.integerLength(2)))):\(seconds.formatted(.number.precision(.integerLength(2))))"
        }
        else {
            return "\(minutes):\(seconds.formatted(.number.precision(.integerLength(2))))"
        }
    }
}
