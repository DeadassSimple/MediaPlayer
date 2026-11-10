//
//  ContentView.swift
//  DeadassSimpleMusicPlayer
//
//  Created by Ky on 2024-06-08.
//

import SwiftUI

import BasicMathTools
import SimpleLogging



struct ContentView: View {
    
    @Environment(\.scenePhase)
    private var scenePhase
    
    @State
    private var showFileBrowser = false
    
    @State
    private var showLibrary = false
    
    /// Owns all durable playback state (the queue, modes, history, saved playlists) and its persistence
    @State
    private var session = PlayerSession()
    
    var body: some View {
        NavigationStack {
            CustomMediaPlayer(session: session)
            
                .playerControls(configuration: controlsConfiguration) { [session] action in
                    await session.perform(action)
                }
            
                .toolbar {
                    ToolbarItemGroup {
                        Button {
                            showLibrary = true
                        } label: {
                            Label("Library", systemImage: "music.note.list")
                        }
                        .labelStyle(.titleAndIcon)
                        
                        Button {
                            showFileBrowser = true
                        } label: {
                            Label("Open", systemImage: "folder")
                        }
                        .labelStyle(.titleAndIcon)
                    }
                }
            
            
                .sheet(isPresented: $showLibrary) {
                    LibraryView(session: session)
                }
            
            
                .fileImporter(isPresented: $showFileBrowser, allowedContentTypes: .init(Playlist.defaultAllowedContentTypes)) { result in
                    switch result {
                    case .success(let openedUrl):
                        Task {
                            let newEntries = await session.withLoadingMessage("Loading folder…") {
                                await Playlist.entries(fromUrl: openedUrl, allowRecursion: true)
                            }
                            session.nowPlaying.queue.append(contentsOf: newEntries)
                            
                            // A quiet background courtesy, after the music's already going: files sharing album metadata become an album playlist
                            await session.library.autoGroupAlbums(from: newEntries)
                        }
                        
                    case .failure(let failure):
                        log(error: failure)
                    }
                }
        }
        
        
        .task {
            await session.loadIfNeeded()
        }
        
        
        // Backgrounding is the canonical "the user might never come back" moment, so whatever's pending gets flushed here
        .onChange(of: scenePhase) { _, newPhase in
            if .active != newPhase {
                session.nowPlaying.saveSnapshotNow()
            }
        }
    }
}



// MARK: - Player controls

private extension ContentView {
    
    /// What the player controls show. This value shows the state of the engine of `session`. Thus the controls agree with the player also when the change comes from outside the app, for example a pause from Control Center.
    var controlsConfiguration: PlayerControlsConfiguration {
        PlayerControlsConfiguration(isPlaying: session.engine.isPlaying)
    }
}



// In the UI layer on purpose: `PlayerAction` is a type of the UI, and the model layer must not depend on it
private extension PlayerSession {
    
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
            nowPlaying.skipToPreviousEntry()
            
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



#Preview {
    ContentView()
}
