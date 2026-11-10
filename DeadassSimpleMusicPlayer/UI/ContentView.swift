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
        PlayerControlsConfiguration(
            isPlaying: session.engine.isPlaying,
            currentTrackPosition: session.engine.currentTrackPosition,
            backForwardKind: .skipTrack)
    }
}



#Preview {
    ContentView()
}
