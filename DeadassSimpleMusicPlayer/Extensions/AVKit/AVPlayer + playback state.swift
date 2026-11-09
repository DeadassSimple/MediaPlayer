//
//  AVPlayer + playback state.swift
//  DeadassSimpleMusicPlayer
//
//  Created by Ky directing Claude Opus 5.5 on 2026-11-06.
//

import AVFoundation



extension AVPlayer {
    
    /// `true` when the rate of the player is not zero. A negative rate (reverse playback) also counts as playing.
    ///
    /// The rate is the rate that the app set. Thus this value stays `true` while the player waits for data. To find if the player waits, read `timeControlStatus`.
    var isPlaying: Bool {
        0 != rate
    }
    
    
    /// `true` when the rate of the player is zero. This value is always the opposite of `isPlaying`.
    @inline(__always)
    var isPaused: Bool {
        !isPlaying
    }
    
    
    /// `true` when the playhead is at the end of the current item, or after it. `false` when no item is loaded, and while the duration of the item is not known.
    var isAtEndOfCurrentItem: Bool {
        if let currentItem,
           currentItem.duration.isNumeric
        {
            return 0 <= CMTimeCompare(currentTime(), currentItem.duration)
        }
        else {
            return false
        }
    }
    
    
    /// Starts playback. If the playhead is at the end of the current item, this function first moves the playhead to the start of the item.
    ///
    /// Use this function, not `play()`, for each play command from the user. `play()` does not start an item again after the item played to its end. Thus, at the end of an item, `play()` does nothing. This function starts the item again, as the playback controls of the system do.
    func playOrRestart() {
        if isAtEndOfCurrentItem {
            seek(to: .zero)
        }
        
        play()
    }
}
