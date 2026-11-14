//
//  ancillary types.swift
//  DeadassSimpleMusicPlayer
//
//  Created by Ky on 2026-11-09.
//

import Foundation



/// Describes the position of a playhead in the context of a single media file
public struct PlayheadPosition: Sendable, Equatable {
    public let current: Duration
    public let total: Duration
}



public extension PlayheadPosition {
    init(current: TimeInterval, total: TimeInterval) {
        self.init(
            current: .seconds(current),
            total: .seconds(total),
        )
    }
}
