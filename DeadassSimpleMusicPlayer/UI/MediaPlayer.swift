//
//  MediaPlayer.swift
//  DeadassSimpleMusicPlayer
//
//  Created by Ky directing Claude Opus 5.5 on 2026-11-06.
//

import SwiftUI



/// A media player for SwiftUI that plays the files you give it. It includes all of the functions of a media player.
///
/// Use this view when you only want to play files. It makes its own `PlayerSession`, so the remote commands, the Now Playing info and picture-in-picture work with no more code. It keeps no history and no library, and it writes nothing to disk. To keep a queue, a history or a library, make a `PlayerSession` and give it to `CustomMediaPlayer`.
///
/// ```swift
/// MediaPlayer(playing: songUrl)
/// ```
///
/// When the parent view gives different URLs, this view replaces its queue with the new files. A folder URL plays all of the media in that folder and in its subfolders.
struct MediaPlayer: View {
    
    /// The files and folders to play, in sequence
    private let urls: [URL]
    
    /// `true` starts playback when the files are loaded
    private let autoplay: Bool
    
    /// Holds the session of this view for the life of the view
    @State
    private var sessionHolder = SessionHolder()
    
    
    /// Plays the given files and folders
    /// - Parameters:
    ///   - urls:     The files and folders to play, in sequence
    ///   - autoplay: `true` starts playback when the files are loaded. Defaults to `true`.
    init(playing urls: [URL], autoplay: Bool = true) {
        self.urls = urls
        self.autoplay = autoplay
    }
    
    
    /// Plays the given file or folder
    /// - Parameters:
    ///   - url:      The file or folder to play
    ///   - autoplay: `true` starts playback when the file is loaded. Defaults to `true`.
    init(playing url: URL, autoplay: Bool = true) {
        self.init(playing: [url], autoplay: autoplay)
    }
    
    
    var body: some View {
        CustomMediaPlayer(session: sessionHolder.session)
            .task(id: urls) {
                await sessionHolder.replaceQueue(with: urls, autoplay: autoplay)
            }
    }
}



private extension MediaPlayer {
    
    /// Holds the session of a `MediaPlayer`, and makes the session the first time something reads it.
    ///
    /// SwiftUI keeps the first value of a `@State` property for the life of the view. But each time a parent view calls `MediaPlayer.init`, Swift makes the initial value again, and SwiftUI discards it. A discarded holder costs almost nothing, because it makes no session. Only the holder that SwiftUI keeps makes a session (and thus a `PlaybackEngine` and an `AVPlayer`), when `body` first reads `session`.
    ///
    /// Thus `CustomMediaPlayer` gets its session in the first frame, and the layout does not jump while the holder makes the session.
    @MainActor
    final class SessionHolder {
        
        /// The session of the `MediaPlayer`. It keeps nothing on disk.
        lazy var session = PlayerSession(persisting: false)
        
        /// The URLs that are in the queue at this time, or `nil` before the first load. A `.task` runs again when the view shows again, and this value prevents a second load of the same URLs.
        private var queuedUrls: [URL]? = nil
        
        
        /// Replaces the queue with the media at `urls`. This function does nothing when the queue contains `urls`.
        ///
        /// - Parameters:
        ///   - urls:     The files and folders to play, in sequence
        ///   - autoplay: `true` starts playback when the files are loaded
        func replaceQueue(with urls: [URL], autoplay: Bool) async {
            if urls == queuedUrls {
                return
            }
            
            var entries: [PlaylistEntry] = []
            
            for url in urls {
                entries.append(contentsOf: await Playlist.entries(fromUrl: url, allowRecursion: true))
            }
            
            if Task.isCancelled {
                return // The URLs changed (or the view went away) during the load, and a newer load or none should win
            }
            
            session.nowPlaying.queue = Playlist(entries: entries)
            queuedUrls = urls
            
            if autoplay {
                session.engine.play()
            }
        }
    }
}
