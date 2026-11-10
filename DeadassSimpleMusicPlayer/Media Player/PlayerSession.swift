//
//  PlayerSession.swift
//  DeadassSimpleMusicPlayer
//
//  Created by Ky directing Claude 5 Fable on 2026-07-01.
//

import Foundation
import Observation

import CollectionTools
import SimpleLogging



/// How long to let a track play before the "previous track" button becomes a "restart this track" button.
///
/// When playing a track, tapping the ⏮️ button returns the playhead to the start of the track. Tapping it again brings it to the start of the previous track.
/// This value tells the player how far into the track one must be for that to be the behavior. Before this number of seconds, it skips to the previous track. After this number of seconds, it returns to the start of this track.
private let skipBackThreshold: TimeInterval = 1.5



/// Connects the playback engine with the queue, the history and the saved playlists. To play media, a view must have only this object.
///
/// Make 1 session, and keep it for the life of the app. Give it to `CustomMediaPlayer` to show its media. To use 1 part directly, use these properties:
/// - `engine` (`PlaybackEngine`): plays 1 item. It owns the `AVPlayer`, does not know about queues, and saves nothing.
/// - `nowPlaying` (`NowPlayingStore`): the queue and the `RepeatMode`. It saves them, and tells the engine which item to load.
/// - `history` (`HistoryStore`): what played. It saves the history.
/// - `library` (`PlaylistLibraryStore`): the saved playlists. It saves them.
///
/// The names show the difference. A `Store` keeps data that stays when nothing is loaded, and it saves that data. The `Engine` plays the loaded item, and it saves nothing.
///
/// The session does only the work that uses more than 1 part:
/// - It restores the previous session.
/// - It adds items to the history when they played for sufficient time.
/// - It saves the queue as a playlist, and loads a playlist into the queue.
/// - It shows `loadingMessage`.
///
/// The session reads the events of the engine. Thus it moves the queue to the next entry when an item plays to its end.
@MainActor
@Observable
public final class PlayerSession {
    
    /// A message that tells the user what loads at this time (for example, the previous session, or a folder), or `nil` when nothing loads.
    ///
    /// While this message is not `nil`, the player screen shows it and not the empty state. To show a message during a long operation, use `withLoadingMessage(_:perform:)`. Do not set this property directly. The function puts back the previous message after the operation. Thus 2 operations at the same time do not erase the message of each other.
    public private(set) var loadingMessage: LocalizedStringResource? = nil
    
    /// Plays the item of the current entry
    public let engine: PlaybackEngine
    
    /// The queue and the repeat mode
    public let nowPlaying: NowPlayingStore
    
    /// What played
    public let history: HistoryStore
    
    /// The saved playlists
    public let library: PlaylistLibraryStore
    
    
    // MARK: Non-observable internals
    
    /// The ID of the last entry that went into the history. Thus 1 arrival at an entry adds only 1 history entry, when the engine reports the position many times.
    @ObservationIgnored
    private var historyRecordedEntryID: PlaylistEntry.ID? = nil
    
    /// `true` after `loadIfNeeded()` started. Thus the restore occurs only 1 time.
    @ObservationIgnored
    private var hasRestored = false
    
    
    /// Makes a session, and starts to read the events of its engine.
    ///
    /// - Parameter persisting: `true` keeps the data on disk. Use `false` where the session must not change data on disk. For example, use `false` in SwiftUI previews, and in `MediaPlayer`, which plays files for a host app. Defaults to `true`.
    public init(persisting: Bool = true) {
        var playerStore: JSONDocumentStore? = nil
        var playlistsStore: JSONDocumentStore? = nil
        
        if persisting {
            do {
                playerStore = try JSONDocumentStore(subfolder: "Player")
                playlistsStore = try JSONDocumentStore(subfolder: "Playlists")
            }
            catch {
                log(error: error, "Persistence is unavailable, so this session will run memory-only")
                playerStore = nil
                playlistsStore = nil
            }
        }
        
        let engine = PlaybackEngine()
        self.engine = engine
        self.nowPlaying = NowPlayingStore(engine: engine, documentStore: playerStore)
        self.history = HistoryStore(documentStore: playerStore)
        self.library = PlaylistLibraryStore(documentStore: playlistsStore)
        
        // The loop ends when the engine ends its streams, which it does when it is released along with this session
        Task { [weak self, events = engine.events()] in
            for await event in events {
                self?.handle(event)
            }
        }
    }
}



// MARK: - Restoring the previous session

public extension PlayerSession {
    
    /// Reads what the previous session saved: the queue (and finds each of its files again), the playback position, the repeat mode, the history, and the saved playlists.
    ///
    /// You can call this function many times. Only the first call does the restore.
    func loadIfNeeded() async {
        guard !hasRestored else { return }
        hasRestored = true
        
        loadingMessage = [
            // By people:
            "Reticulating splines…",
            "Gimme sec…",
            "Hang on…",
            "Uhhhhhhhh…",
            "Where did I leave the music…",
            "Where did I leave the movies…",
            "Where did I leave the shoes…",
            "Where did I leave the videos…",
            "Where did I leave the files…",
            "…",
            "Lemme get uhhhhh…",
            "𝔗𝔥𝔢…",
            "Preparing to load…",
            "Loading…",
            "Loading preparation…",
            "Hacking the planet…",
            "Curing cancer real quick…",
            "🥕…",
            "Wiping fingerprints off CD…",
            "Tuning stereo…",
            "Adjusting tracking…",
            "Flipping to Side B…",
            "Renoising…",
            "I'll be there in a sec…",
            "When was it due…",
            "Dusting records…",
            "Loading vocoder?…",
            "?…",
            "Honey, where are my pants…",
            "Daisy, Daisy…",
            "Recalculating route…",
            "Recalcitrating splines…",
            "Spilling popcorn…",
            "Blowing in cartridge…",
            "ignoring The Cloud…",
            "Waxing cylinders…",
            "Waxing poetic…",
            "I'll have two #9s…",
            "Animating hills…",
            "Pirating music…",
            "Pirating movies…",
            "Pirating shoes…",
            "Pirating anime…",
            "Pirating \"anime\"…",
            "Pirating Weird Al's \"Don't Download This Song\"…",
            "Pirating K-Pop…",
            "Pirating A-Pop…",
            "Loading slower…",
            "Loading faster…",
            "Normalizing oddities…",
            "Deciding what to display next…",
            "Loading loading messages…",
            "Messaging loading message loader…",
            "Counting songs…",
            "Discounting songs…",
            "Bypassing…",
            "Ranking music…",
            "Calling a librarian…",
            "Drawing a furry…",
            "Inventing genres…",
            "Pretending…",
            "Hear me out…",
            "Gesticulating mimes…",
            "[Loading, in Spanish…]",
            "Stirring genetic pool…",
            "Confounding an AI…",
            "Low ding…",
            "Obfuscating quigly matrix…",
            "Finishing random walk…",
            "Activating god mode…",
            "Becoming dumber…",
            "Searching for llamas…",
            "Looking for remote…",
            "Playing infrasound…",
            "Playing God…",
            "Playing Dog…",
            "Learning about filetypes…",
            "Losing keys…",
            "Defying gravity…",
            "Almost done…",
            "Almost Dunn…",
            "Lemme just scootch past ya…",
            "Eating cookies…",
            "Untangling AirPods…",
            "Sorting randomness…",
            "Switching…",
            "Dissociating…",
            "Integrating…",
            
            // By Claude:
            "Consulting elders…",
            "Downloading more RAM…",
            "Untangling headphones…",
            "Rolling for initiative…",
            "Doing crimes…",
            "Touching grass…",
            "Turning it off and on again…",
        ].randomElement() ?? "Loading..."
        defer { loadingMessage = nil }
        
        await nowPlaying.load()
        history.load()
        library.load()
    }
}



// MARK: - Loading indication

public extension PlayerSession {
    
    /// Shows `message` as `loadingMessage` while `work` runs. When `work` is complete, this function puts back the message that was there before, which is not always `nil`.
    /// 
    /// Thus 2 operations can run at the same time, and the operation that completes first does not erase the message of the other. For example, a short folder import can complete while the restore of the previous session continues.
    ///
    /// - Parameters:
    ///   - message: The message to show while `work` runs
    ///   - work:    The operation
    ///
    /// - Returns: The value that `work` returns
    func withLoadingMessage<T>(_ message: LocalizedStringResource, perform work: () async -> T) async -> T {
        let previousMessage = loadingMessage
        loadingMessage = message
        defer { loadingMessage = previousMessage }
        return await work()
    }
}



// MARK: - Playback events

public extension PlayerSession {
    
    /// How long a file must play, in seconds, before it goes into the history. A file that is shorter than this goes into the history when it plays to its end.
    static let historyThresholdSeconds = 1.0
}



private extension PlayerSession {
    
    /// Changes the queue and the history for 1 event from the engine.
    ///
    /// An event can come after a different item loaded. Thus this function ignores an event about an item that is not the item of the current entry.
    func handle(_ event: PlaybackEngine.Event) {
        switch event {
        case .positionChanged(item: let item, seconds: let seconds):
            if isCurrent(item) {
                nowPlaying.notePlaybackPosition(seconds: seconds)
                
                if seconds >= Self.historyThresholdSeconds {
                    recordCurrentEntryInHistoryIfNeeded()
                }
            }
            
        case .finished(item: let item):
            if isCurrent(item) {
                recordCurrentEntryInHistoryIfNeeded() // Also how a file shorter than `historyThresholdSeconds` gets into history
                nowPlaying.advanceAfterCurrentItemFinished()
            }
            else {
                log(info: "Ignored the end of an item which is no longer current")
            }
            
        case .paused:
            nowPlaying.saveSnapshotNow() // Pausing is a moment the user implicitly expects their place to be remembered
        }
    }
    
    
    /// `true` when `item` is the item of the current entry of the queue
    func isCurrent(_ item: MediaItem) -> Bool {
        nowPlaying.queue.currentEntry?.mediaItem == item
    }
    
    
    /// Adds the current entry to the history, 1 time for each arrival at that entry.
    ///
    /// The callers make the decision about when the file played for sufficient time. This function ignores the calls after the first. Thus the callers can call it many times.
    func recordCurrentEntryInHistoryIfNeeded() {
        guard let entry = nowPlaying.queue.currentEntry,
              historyRecordedEntryID != entry.id
        else { return }
        
        historyRecordedEntryID = entry.id
        history.record(entry.reference, displayName: displayName(for: entry))
    }
}



// In the UI layer on purpose: `PlayerAction` is a type of the UI, and the model layer must not depend on it
public extension PlayerSession {
    
    /// Changes playback for 1 action that the user did in the player controls.
    ///
    /// Call this function from the `onUserAction` closure of `playerControls(configuration:onUserAction:)`.
    ///
    /// - Parameter action: The action that the user did
    func perform(_ action: PlayerAction) {
        switch action {
        case .play:
            engine.play()
            
        case .pause:
            engine.pause()
            
        case .previousTrack:
            if engine.currentTime < skipBackThreshold {
                nowPlaying.skipToPreviousEntry()
            }
            else {
                engine.seek(to: .zero)
            }
            
        case .nextTrack:
            nowPlaying.skipToNextEntry()
            
        case .skipBackward(increment: let increment):
            // `currentTime` can be up to 1 interval of the periodic time observer behind the player during playback
            seekWithinCurrentItem(to: engine.currentTime - (increment / .seconds(1)))
            
        case .skipForward(increment: let increment):
            seekWithinCurrentItem(to: engine.currentTime + (increment / .seconds(1)))
            
        case .reverse(transaction: let transaction),
                .fastForward(transaction: let transaction),
                .scrub(transaction: let transaction):
            // A `TransportTransaction` has positions and no rate, so the controls calculate the position, and `perform(_:)` only moves the playhead to that position
            seekWithinCurrentItem(to: transaction.currentPosition / .seconds(1))
        }
    }
    
    
    /// Moves the playhead of the engine to `seconds`, but not before the start of the loaded item, and not after its end.
    ///
    /// When the duration of the item is not known, the start of the item is the only limit.
    ///
    /// - Parameter seconds: The new position, in seconds from the start of the loaded item
    func seekWithinCurrentItem(to seconds: TimeInterval) {
        guard seconds.isFinite else {
            log(error: "Ignored a seek to a position which is not a finite number: \(seconds)")
            return
        }
        
        engine.seek(to: seconds.clamped(within: 0 ... (engine.duration ?? .infinity)))
    }
}



// MARK: - Between the queue and the library

public extension PlayerSession {
    
    /// Saves the entries of the queue, in the sequence that the user selected, as a new saved playlist
    /// - Parameter name: The name of the new playlist
    /// - Returns: The new playlist
    @discardableResult
    func saveQueueAsPlaylist(named name: String) -> SavedPlaylist {
        let playlist = SavedPlaylist(name: name, savingQueue: nowPlaying.queue)
        library.upsert(playlist)
        return playlist
    }
    
    
    /// Imports an M3U or M3U8 playlist, and compares its entries with all files that this session knows. These files come from the saved playlists, the queue, and the history. Refer to `PlaylistLibraryStore.importPlaylist(fromM3U8:suggestedName:matchingAgainst:)`.
    ///
    /// - Parameters:
    ///   - data:          The contents of the playlist file
    ///   - suggestedName: The name of the imported playlist, usually the name of the file
    ///
    /// - Returns: The saved playlist and the number of entries that could not be imported, or `nil` when `data` is not a correct playlist
    func importPlaylist(fromM3U8 data: Data, suggestedName: String) -> (SavedPlaylist, failedTrackImportCount: Int)? {
        library.importPlaylist(fromM3U8: data, suggestedName: suggestedName, matchingAgainst: allKnownReferencesByFilename())
    }
}



private extension PlayerSession {
    
    /// Returns the name to show for `entry` in the history: the title from the metadata when the search found it, and the filename when not
    func displayName(for entry: PlaylistEntry) -> String {
        if let metadata = entry.mediaItem?.metadata,
           let foundTitle = (try? metadata.get(.title).value) ?? nil,
           let title = foundTitle.nonEmptyOrNil
        {
            return title
        }
        
        return entry.reference.displayName
    }
    
    
    /// Returns all files that the app has access to, with the filename of each as its key. The M3U8 import compares its entries with these files.
    ///
    /// This function reads the sources in this sequence: the history, then the saved playlists, then the queue. When 2 files have the same name, the file from the last source wins.
    func allKnownReferencesByFilename() -> [String: MediaReference] {
        var known: [String: MediaReference] = [:]
        
        let allReferences = history.entries.map(\.reference)
            + library.savedPlaylists.flatMap(\.items)
            + nowPlaying.queue.entries.map(\.reference)
        
        for reference in allReferences {
            known[reference.filename] = reference
        }
        
        return known
    }
}
