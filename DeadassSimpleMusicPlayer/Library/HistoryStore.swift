//
//  HistoryStore.swift
//  DeadassSimpleMusicPlayer
//
//  Created by Ky directing Claude Fable 5.1 on 2026-09-06.
//

import Foundation
import Observation

import SimpleLogging



/// Keeps the history of what played, and saves it to disk.
///
/// Use this store to show the history, to change how much history to keep, or to remove the history. The history stays when nothing is loaded, and it comes back after the app starts again.
///
/// Each change saves to disk immediately. Changes to the history do not occur frequently. Thus each change can go to disk immediately with no performance problem.
///
/// This store does not make the decision about when a file played for sufficient time. `PlayerSession` makes that decision, because it has the queue and the engine. Then it calls `record(_:displayName:)`.
@MainActor
@Observable
public final class HistoryStore {
    
    #if DEBUG
    /// What played. Change the history through the methods of this store (for example, `record(_:displayName:)`). Then each change goes to disk immediately. Debug builds can set this property directly, for demo data.
    public var playbackHistory = PlaybackHistory()
    #else
    /// What played. Change the history through the methods of this store (for example, `record(_:displayName:)`). Then each change goes to disk immediately.
    public private(set) var playbackHistory = PlaybackHistory()
    #endif
    
    /// What played, with the newest entry first
    public var entries: [PlaybackHistory.Entry] {
        playbackHistory.entries
    }
    
    /// How much history to keep.
    ///
    /// A change removes the entries that the new value does not keep, and saves to disk immediately. You can bind a SwiftUI control to this property.
    public var retention: PlaybackHistory.Retention {
        get {
            playbackHistory.retention
        }
        set {
            playbackHistory.retention = newValue
            saveNow()
        }
    }
    
    /// Where this store keeps its data on disk, or `nil` when this store runs memory-only
    private let documentStore: JSONDocumentStore?
    
    
    /// - Parameter documentStore: Where to keep the data on disk, or `nil` to run memory-only (for example, in SwiftUI previews)
    public init(documentStore: JSONDocumentStore?) {
        self.documentStore = documentStore
    }
}



// MARK: - Restoring

public extension HistoryStore {
    
    /// Reads the history from disk, and removes the entries that `retention` does not keep. The app was closed for some time. Thus `retention` can remove some entries at this time.
    ///
    /// This function does nothing when this store runs memory-only, and when no history was saved.
    func load() {
        guard let documentStore else { return } // Expected when this store runs memory-only, so there is nothing to report
        
        do {
            if var restoredHistory = try documentStore.load(PlaybackHistory.self, named: Self.historyDocumentName) {
                restoredHistory.applyRetention()
                playbackHistory = restoredHistory
            }
        }
        catch {
            log(error: error, "The play history document exists but couldn't be read")
        }
    }
}



// MARK: - Recording & management

public extension HistoryStore {
    
    /// Adds a file to the history, and saves the history to disk
    /// - Parameters:
    ///   - reference:   The file that played
    ///   - displayName: The name to show for the entry in a list
    func record(_ reference: MediaReference, displayName: String) {
        playbackHistory.record(reference, displayName: displayName)
        saveNow()
    }
    
    
    /// Removes all entries from the history, and saves the history to disk
    func clear() {
        playbackHistory.clear()
        saveNow()
    }
}



private extension HistoryStore {
    
    /// The name of the document that contains the history
    static let historyDocumentName = "History"
    
    
    /// Saves the history to disk immediately
    func saveNow() {
        guard let documentStore else { return } // Expected when this store runs memory-only, so there is nothing to report
        
        do {
            try documentStore.save(playbackHistory, named: Self.historyDocumentName)
        }
        catch {
            log(error: error, "Couldn't save the play history")
        }
    }
}
