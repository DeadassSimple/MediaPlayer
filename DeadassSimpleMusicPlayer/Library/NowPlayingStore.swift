//
//  NowPlayingStore.swift
//  DeadassSimpleMusicPlayer
//
//  Created by Ky directing Claude Fable 5.1 on 2026-09-06.
//

import Foundation
import Observation

import SimpleLogging



/// Keeps the queue and the repeat mode, saves them to disk, and tells the `PlaybackEngine` which item to load.
///
/// Use this store to read or change what plays at this time and what plays next. The queue and the repeat mode stay when nothing is loaded, and they come back after the app starts again.
///
/// When the current entry of the queue changes, this store loads the item of that entry into the engine, in the same step. Thus the item in the engine always agrees with the current entry.
///
/// This store saves its data when the data changes. Thus you do not call a save function after each change:
/// - A change to the queue or to the repeat mode saves after a short time. Thus a fast sequence of changes (for example, an import of a folder) causes only 1 write.
/// - A change of the playback position saves after a longer time, because the position changes all the time during playback.
/// - `saveSnapshotNow()` saves immediately. Call it at the moments when the user wants their position to be safe, for example when the app goes to the background.
@MainActor
@Observable
public final class NowPlayingStore {
    
    /// The entries that play at this time and after.
    ///
    /// You can change the queue directly, also through a SwiftUI binding. The store saves each change. When the change moves the current entry to a different item, the store loads that item into the engine, paused. Thus a change such as the removal of the current entry does not start playback. To play the new current entry, use `play(entryWithID:)` or call `PlaybackEngine.play()`.
    public var queue: Playlist = .empty {
        didSet {
            guard !isRestoring else { return }
            scheduleSnapshotSave(within: Self.structuralSaveDebounce)
            
            let previousItem = oldValue.currentEntry?.mediaItem
            let currentItem = queue.currentEntry?.mediaItem
            if previousItem != currentItem {
                playbackPositionSeconds = nil // A position in the previous item must never be saved as the position of this one
                engine.load(currentItem, autoplay: false)
            }
        }
    }
    
    /// What the engine does when the current item plays to its end. The store saves this value with the queue. Saved playlists do not contain it.
    public var repeatMode: RepeatMode = .off {
        didSet {
            guard !isRestoring else { return }
            scheduleSnapshotSave(within: Self.structuralSaveDebounce)
        }
    }
    
    /// The engine that this store loads items into
    public let engine: PlaybackEngine
    
    
    // MARK: Non-observable internals
    
    /// The playback position in the item of the current entry, in seconds, or `nil` when the position is not known. The snapshot contains this value, so the next start of the app can continue from the same position.
    @ObservationIgnored
    private var playbackPositionSeconds: Double? = nil
    
    /// `true` only while `load()` sets the restored values. Thus the `didSet` observers do not save or load again what `load()` sets directly.
    @ObservationIgnored
    private var isRestoring = false
    
    /// The scheduled snapshot save, or `nil` when no save is scheduled
    @ObservationIgnored
    private var pendingSnapshotSave: Task<Void, Never>? = nil
    
    /// The time of the scheduled snapshot save, or `nil` when no save is scheduled
    @ObservationIgnored
    private var pendingSnapshotSaveDeadline: ContinuousClock.Instant? = nil
    
    /// Where this store keeps its data on disk, or `nil` when this store runs memory-only
    private let documentStore: JSONDocumentStore?
    
    
    /// - Parameters:
    ///   - engine:        The engine to load the item of the current entry into
    ///   - documentStore: Where to keep the data on disk, or `nil` to run memory-only (for example, in SwiftUI previews)
    public init(engine: PlaybackEngine, documentStore: JSONDocumentStore?) {
        self.engine = engine
        self.documentStore = documentStore
    }
}



// MARK: - Restoring the previous session

public extension NowPlayingStore {
    
    /// Reads the queue, the repeat mode and the playback position that the previous session saved.
    ///
    /// Then this function loads the current entry into the engine, paused, at that position. The store finds each file of the queue again, which can be slow for a large queue.
    ///
    /// This function does nothing when this store runs memory-only, and when no previous session saved data.
    func load() async {
        guard let documentStore else { return } // Expected when this store runs memory-only, so there is nothing to report
        
        // All the slow, suspending work happens into locals first; assignment at the bottom is synchronous, so the `isRestoring` gate can't accidentally swallow a save for some unrelated mutation which interleaves with a suspension here
        
        var restoredQueue: Playlist? = nil
        var restoredRepeatMode: RepeatMode? = nil
        var restoredPositionSeconds: Double? = nil
        
        do {
            if let snapshot = try documentStore.load(NowPlayingSnapshot.self, named: Self.nowPlayingDocumentName) {
                restoredQueue = await snapshot.restoredPlaylist()
                restoredRepeatMode = snapshot.repeatMode
                restoredPositionSeconds = snapshot.playbackPositionSeconds
            }
        }
        catch {
            log(error: error, "The previous session's Now Playing snapshot exists but couldn't be read")
        }
        
        
        isRestoring = true
        defer { isRestoring = false }
        
        if let restoredQueue {
            queue = restoredQueue
            playbackPositionSeconds = restoredPositionSeconds
            
            log(info: "Restored the previous session: \(restoredQueue.entries.count) queue entries, playback position \(restoredPositionSeconds.map { "\($0)s" } ?? "unknown")")
            
            // Loaded here rather than by the `queue` observer (gated off during restore), so the restored position can ride along with the load instead of being parked for someone else to claim
            engine.load(restoredQueue.currentEntry?.mediaItem, resumingAt: restoredPositionSeconds, autoplay: false)
        }
        
        if let restoredRepeatMode {
            repeatMode = restoredRepeatMode
        }
    }
}



// MARK: - Playback intent

public extension NowPlayingStore {
    
    /// Makes the entry with the given ID the current entry, and starts playback.
    ///
    /// When the entry is the current entry, playback continues or starts. When the item of the entry played to its end, playback starts again at the start of the item.
    ///
    /// This function does nothing when the file of the entry is not available.
    func play(entryWithID id: PlaylistEntry.ID) {
        guard queue.entry(withID: id)?.isPlayable ?? false else { return }
        
        queue.currentEntryID = id // Loads it into the engine, paused
        engine.play()
    }
    
    
    /// Adds a history entry to the end of the queue, makes it the current entry, and starts playback. The other entries of the queue do not change.
    ///
    /// A history entry contains only a reference to its file, so this function must find the file again. When the file moved or was deleted, this function logs the error and does nothing more.
    func replay(_ historyEntry: PlaybackHistory.Entry) async {
        guard let item = await MediaItem(resolving: historyEntry.reference) else {
            log(error: "Couldn't reopen “\(historyEntry.displayName)” from history — the file may have moved or been deleted")
            return
        }
        
        let entry = PlaylistEntry(item)
        
        queue.append(entry, allowMovingToNewItem: false)
        queue.currentEntryID = entry.id
        engine.play()
    }
    
    
    /// Replaces the queue with the entries of a saved playlist.
    ///
    /// The store finds each file of the playlist again. A file that the store cannot find becomes an entry that is not available: the queue shows it, and playback skips it. Thus the queue shows the playlist that the user saved.
    ///
    /// - Parameters:
    ///   - playlist: The saved playlist to load
    ///   - andPlay:  `true` starts playback after the load. Defaults to `true`.
    func loadIntoQueue(_ playlist: SavedPlaylist, andPlay: Bool = true) async {
        var entries: [PlaylistEntry] = []
        entries.reserveCapacity(playlist.items.count)
        
        for reference in playlist.items {
            entries.append(await .resolving(reference))
        }
        
        queue = Playlist(entries: entries)
        
        if andPlay,
           nil != queue.currentEntry?.mediaItem
        {
            engine.play()
        }
    }
    
    
    /// Selects what plays after the current item played to its end. The result changes with `repeatMode`.
    ///
    /// Call this function when the engine sends `PlaybackEngine.Event.finished(item:)` for the item of the current entry.
    func advanceAfterCurrentItemFinished() {
        switch repeatMode {
        case .currentItem:
            engine.replayFromStart()
            
        case .wholeQueue:
            if nil != queue.moveToNextEntry(wrapping: true) {
                engine.play()
            }
            else {
                // Wrapping with nowhere else to go (the queue's only playable entry is this one) still means "start over"
                engine.replayFromStart()
            }
            
        case .off:
            if nil != queue.moveToNextEntry(wrapping: false) {
                engine.play()
            }
            // Otherwise the queue is finished, and the player rests at the end of the final file
        }
    }
}



// MARK: - Saving

public extension NowPlayingStore {
    
    /// Records the playback position in the item of the current entry, so the next start of the app can continue from that position.
    ///
    /// This function saves to disk only after some time, because the position changes all the time during playback. Thus after a crash, the saved position can be some seconds before the correct position. The saved queue is always correct.
    func notePlaybackPosition(seconds: Double) {
        guard seconds.isFinite,
              seconds >= 0
        else { return }
        
        playbackPositionSeconds = seconds
        scheduleSnapshotSave(within: Self.positionSaveThrottle)
    }
    
    
    /// Saves the queue, the repeat mode and the playback position immediately. A save that was scheduled is then not necessary, so this function cancels it.
    ///
    /// Call this function when the user wants their position to be safe. For example, call it when playback pauses, and when the app goes to the background.
    func saveSnapshotNow() {
        pendingSnapshotSave?.cancel()
        pendingSnapshotSave = nil
        pendingSnapshotSaveDeadline = nil
        
        guard let documentStore else { return } // Expected when this store runs memory-only, so there is nothing to report
        
        do {
            try documentStore.save(
                NowPlayingSnapshot(
                    of: queue,
                    playbackPositionSeconds: playbackPositionSeconds,
                    repeatMode: repeatMode),
                named: Self.nowPlayingDocumentName)
        }
        catch {
            log(error: error, "Couldn't save the Now Playing snapshot")
        }
    }
}



private extension NowPlayingStore {
    
    /// The name of the document that contains the snapshot
    static let nowPlayingDocumentName = "Now Playing"
    
    /// The time before the store saves a change to the queue or to the modes. Thus a fast sequence of changes (for example, an import of 200 files) causes only 1 write.
    static let structuralSaveDebounce = Duration.seconds(1)
    
    /// The time before the store saves a change of the playback position. The position changes all the time during playback. After a crash, a saved position that is some seconds before the correct position is satisfactory, and this time prevents too many writes to storage.
    static let positionSaveThrottle = Duration.seconds(5)
    
    
    /// Makes sure that a snapshot save occurs at the latest `delay` after this call.
    ///
    /// When a save is scheduled at or before that time, this function does nothing. If not, this function moves the scheduled save to that time. Thus fast changes to the queue and slow changes of the position share 1 scheduled save.
    func scheduleSnapshotSave(within delay: Duration) {
        let deadline = ContinuousClock.now + delay
        
        if nil != pendingSnapshotSave,
           let existingDeadline = pendingSnapshotSaveDeadline,
           existingDeadline <= deadline
        {
            return
        }
        
        pendingSnapshotSave?.cancel()
        pendingSnapshotSaveDeadline = deadline
        
        pendingSnapshotSave = Task { [weak self] in
            do {
                try await Task.sleep(until: deadline, clock: .continuous)
            }
            catch {
                return // Cancelled: a sooner schedule or an immediate save superseded this one
            }
            
            self?.saveSnapshotNow()
        }
    }
}
