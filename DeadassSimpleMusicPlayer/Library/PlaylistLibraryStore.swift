//
//  PlaylistLibraryStore.swift
//  DeadassSimpleMusicPlayer
//
//  Created by Ky directing Claude Fable 5.1 on 2026-09-06.
//

import Foundation
import Observation

import CollectionTools
import SimpleLogging



/// Keeps the playlists that the user saved, and saves them to disk.
///
/// Use this store to show, add, change, delete or import saved playlists. The library stays when nothing is loaded, and it comes back after the app starts again.
///
/// Change the library only through the methods of this store. Each method changes the memory and the disk together, so the two always agree.
///
/// This store does not know about the queue. `PlayerSession` saves the queue as a playlist and loads a playlist into the queue, because it has the queue and this store.
@MainActor
@Observable
public final class PlaylistLibraryStore {
    
    #if DEBUG
    /// The saved playlists, sorted by name. Change them through the methods of this store (for example, `upsert(_:)`). Then the memory and the disk always agree. Debug builds can set this property directly, for demo data.
    public var savedPlaylists: [SavedPlaylist] = []
    #else
    /// The saved playlists, sorted by name. Change them through the methods of this store (for example, `upsert(_:)`). Then the memory and the disk always agree.
    public private(set) var savedPlaylists: [SavedPlaylist] = []
    #endif
    
    /// Where this store keeps its data on disk, or `nil` when this store runs memory-only. Each saved playlist is 1 document, with the ID of the playlist as its name.
    private let documentStore: JSONDocumentStore?
    
    
    /// - Parameter documentStore: Where to keep the data on disk, or `nil` to run memory-only (for example, in SwiftUI previews)
    public init(documentStore: JSONDocumentStore?) {
        self.documentStore = documentStore
    }
}



// MARK: - Restoring

public extension PlaylistLibraryStore {
    
    /// Reads all saved playlists from disk. A playlist that this function cannot read stays on disk, but does not go into `savedPlaylists`.
    ///
    /// This function does nothing when this store runs memory-only.
    func load() {
        guard let documentStore else { return } // Expected when this store runs memory-only, so there is nothing to report
        
        do {
            savedPlaylists = try documentStore
                .allDocumentNames()
                .compactMap { name in
                    do {
                        return try documentStore.load(SavedPlaylist.self, named: name)
                    }
                    catch {
                        log(error: error, "Couldn't read the saved playlist document “\(name)”; skipping it (but leaving it on disk)")
                        return nil
                    }
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        catch {
            log(error: error, "Couldn't list the saved playlist documents")
        }
    }
}



// MARK: - Editing

public extension PlaylistLibraryStore {
    
    /// Adds a saved playlist, or replaces the saved playlist that has the same ID. The memory and the disk change together.
    /// - Parameter playlist: The playlist to add or replace
    func upsert(_ playlist: SavedPlaylist) {
        if let existingIndex = savedPlaylists.firstIndex(where: { playlist.id == $0.id }) {
            savedPlaylists[existingIndex] = playlist
        }
        else {
            savedPlaylists.append(playlist)
        }
        
        savedPlaylists.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        
        guard let documentStore else { return } // Expected when this store runs memory-only, so there is nothing to report
        
        do {
            try documentStore.save(playlist, named: playlist.id.uuidString)
        }
        catch {
            log(error: error, "Couldn't save the playlist “\(playlist.name)”")
        }
    }
    
    
    /// Deletes a saved playlist. The memory and the disk change together.
    /// - Parameter id: The ID of the playlist to delete
    /// - Throws: The error from the disk, if this function cannot delete the document of the playlist
    func delete(playlistWithID id: SavedPlaylist.ID) throws {
        savedPlaylists.removeAll { id == $0.id }
        
        guard let documentStore else { return } // Expected when this store runs memory-only, so there is nothing to report
        
        try documentStore.delete(documentNamed: id.uuidString)
    }
}



// MARK: - Importing

public extension PlaylistLibraryStore {
    
    /// Imports a playlist that this app exported as JSON.
    ///
    /// The imported playlist gets a new ID. Thus an import cannot replace a saved playlist that has the same ID, for example when the user imports their own export again. The JSON contains the bookmark data of each file, so on the same device the files of an imported playlist are usually available immediately.
    ///
    /// - Parameter data: The contents of the exported file
    /// - Returns: The imported playlist, or `nil` when `data` is not a playlist that this app exported
    @discardableResult
    func importPlaylist(fromExportedJSON data: Data) -> SavedPlaylist? {
        do {
            var playlist = try JSONDecoder().decode(SavedPlaylist.self, from: data)
            playlist.id = UUID()
            
            upsert(playlist)
            return playlist
        }
        catch {
            log(error: error, "Couldn't import that file as a playlist")
            return nil
        }
    }
    
    
    /// Imports an M3U or M3U8 playlist. This import cannot always find all of the files.
    ///
    /// The sandbox does not let the app open a file from its name only. Thus this function compares the filename of each entry with `knownReferences`, which contains the files that the app has access to. Each file that it finds goes into the imported playlist. This function counts and skips the other entries, and logs the result. A possible future change: let the user find the files that this function cannot find.
    ///
    /// - Parameters:
    ///   - data:            The contents of the playlist file
    ///   - suggestedName:   The name of the imported playlist, usually the name of the file
    ///   - knownReferences: The files that the app has access to, with the filename of each as its key. This store knows only the files of its playlists. `PlayerSession` adds the files of the queue and of the history.
    ///
    /// - Returns: The saved playlist and the number of entries that this function could not import, or `nil` when `data` is not a correct playlist
    func importPlaylist(fromM3U8 data: Data, suggestedName: String, matchingAgainst knownReferences: [String: MediaReference]) -> (SavedPlaylist, failedTrackImportCount: Int)? {
        guard let text = String(data: data, encoding: .utf8) else {
            log(error: "That M3U8 file isn't UTF-8 text, so I can't read it")
            return nil
        }
        
        // The M3U format: one entry per line; lines starting with # are directives/comments, everything else names media
        let entryLines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        
        guard !entryLines.isEmpty else {
            log(error: "No entries found in that M3U8 file")
            return nil
        }
        
        let matchedItems = entryLines.compactMap { line -> MediaReference? in
            // Tolerate other apps' path-style entries by matching on just the final component
            let bareFilename = line
                .split(whereSeparator: { "/" == $0 || "\\" == $0 })
                .last
                .map(String.init)
                ?? line
            
            return knownReferences[bareFilename]
        }
        
        guard !matchedItems.isEmpty else {
            log(error: "None of the \(entryLines.count) entries in that M3U8 matched a file this app has been granted access to, so there's nothing to import. (An M3U8 can only re-assemble files you've already opened here.)")
            return nil
        }
        
        let failedTrackImportCount = entryLines.count - matchedItems.count
        
        if failedTrackImportCount > 0 {
            log(warning: "Imported \(matchedItems.count) of \(entryLines.count) M3U8 entries; the rest named files this app has never been granted access to")
        }
        
        let playlist = SavedPlaylist(name: suggestedName, items: matchedItems)
        upsert(playlist)
        return (playlist, failedTrackImportCount: failedTrackImportCount)
    }
    
    
    /// Makes album playlists from entries that the user imported, with the album metadata of each file.
    ///
    /// When 2 or more files have the same album name, they become a `SavedPlaylist` with `kind` set to `.album`, and with that album name. When the library has an album playlist with that name, the files go into it. A single file does not make an album.
    ///
    /// This function waits for the metadata search of each file. Thus, call it after the entries are in the queue and playback started. Playback must not wait for this function.
    ///
    /// When files go into an album playlist that the library has, this function compares filenames to find duplicates. It does not compare bookmark data, because the bookmark data of 1 file can change. Thus an import of the same album again does not add its tracks 2 times. The tracks keep the sequence of the import. A possible future change: sort the tracks by track number.
    ///
    /// - Parameter entries: The entries that the user imported
    func autoGroupAlbums(from entries: [PlaylistEntry]) async {
        var albumNamesInImportOrder: [String] = []
        var referencesByAlbum: [String: [MediaReference]] = [:]
        
        for entry in entries {
            guard let metadata = entry.mediaItem?.metadata,
                  let albumName = ((try? await metadata.get(.album)) ?? nil)?.nonEmptyOrNil
            else { continue }
            
            if nil == referencesByAlbum[albumName] {
                albumNamesInImportOrder.append(albumName)
            }
            
            referencesByAlbum[albumName, default: []].append(entry.reference)
        }
        
        for albumName in albumNamesInImportOrder {
            guard let references = referencesByAlbum[albumName],
                  references.count >= 2
            else { continue }
            
            if var existingAlbum = savedPlaylists.first(where: { .album == $0.kind && albumName == $0.name }) {
                let existingFilenames = Set(existingAlbum.items.map(\.filename))
                let genuinelyNewItems = references.filter { !existingFilenames.contains($0.filename) }
                
                guard !genuinelyNewItems.isEmpty else { continue }
                
                existingAlbum.items.append(contentsOf: genuinelyNewItems)
                upsert(existingAlbum)
                log(info: "Merged \(genuinelyNewItems.count) new track(s) into the album “\(albumName)”")
            }
            else {
                upsert(SavedPlaylist(name: albumName, kind: .album, items: references))
                log(info: "Auto-grouped \(references.count) tracks into a new album: “\(albumName)”")
            }
        }
    }
}
