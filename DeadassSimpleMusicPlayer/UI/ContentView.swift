//
//  ContentView.swift
//  DeadassSimpleMusicPlayer
//
//  Created by Ky on 2024-06-08.
//

import SwiftUI

import BasicMathTools
import SimpleLogging



/// The current item must be longer than this for the player controls to show the skip-time buttons. An item of this length or shorter gets the skip-track buttons.
///
/// A constant for now. Ky plans to make this a setting.
private let skipTimeMinimumDuration: TimeInterval = 10 * 60

/// How far each skip-time button moves the playhead.
///
/// A constant for now. Ky plans to make this a setting.
private let skipTimeIncrement: PlayerAction.SkipIncrement = .seconds(10)



struct ContentView: View {
    
    // MARK: External state
    
    @Environment(\.scenePhase)
    private var scenePhase
    
    /// Part of the layout decision in `useFullscreenUi`. At this time, the layout does not change with the width.
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass
    
    /// Selects the layout: a compact height shows the media full screen, with no title or artist
    @Environment(\.verticalSizeClass)
    private var verticalSizeClass
    
    
    // MARK: Private state
    
    /// The picture-in-picture state of the player
    @State
    private var pipStatus = Player.PipStatus.undefined
    
    @State
    private var showFileBrowser = false
    
    @State
    private var showLibrary = false
    
    /// Owns all durable playback state (the queue, modes, history, saved playlists) and its persistence
    @State
    private var session = PlayerSession()
    
    /// The newest folder import, or `nil` before the first one. Each import waits for the import before it, and then adds its entries to the queue
    @State
    private var newestFolderImport: Task<Void, Never>? = nil
    
    @State
    private var expansion: TitleBar.Expansion = .collapsed
    
    
    // MARK: `View`
    
    var body: some View {
        NavigationStack {
            main
            
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
                        let previousImport = newestFolderImport
                        newestFolderImport = Task {
                            let newEntries = await session.withLoadingMessage("Loading folder…") {
                                await Playlist.entries(fromUrl: openedUrl, allowRecursion: true)
                            }
                            await previousImport?.value // Folders load at the same time, but go into the queue in the sequence that the user picked them
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



private extension ContentView {
    var main: some View {
        VStack {
            playerView
            
            TitleBar(mode: titleBarMode, expansion: $expansion)
        }
        .background(Color(.secondarySystemBackground))
        .background(ignoresSafeAreaEdges: .all)
    }
}



// MARK: - Player view

private extension ContentView {
    
    /// The engine of `session`
    @inline(__always)
    var engine: PlaybackEngine {
        session.engine
    }
    
    
    /// The media itself: the video, or the cover art for audio
    var playerView: some View {
        Player(player: engine.player, artwork: engine.artwork, pipStatus: $pipStatus)
            .aspectRatio(16/9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .layoutPriority(2)
//            .ignoresSafeArea(.container, edges: useFullscreenUi ? .top : [])
    }
    
    
    var titleBarMode: TitleBar.Mode {
        if let loadingMessage = session.loadingMessage {
            return .appIsLoading(message: LocalizedStringKey(loadingMessage))
        }
        else if let currentItem = engine.currentItem {
            return .loaded(currentItem: currentItem)
        }
        else {
            return .noMedia
        }
    }
}



// MARK: - Player controls

private extension ContentView {
    
    /// What the player controls show. This value shows the state of the engine of `session`. Thus the controls agree with the player also when the change comes from outside the app, for example a pause from Control Center.
    var controlsConfiguration: PlayerControlsConfiguration {
        PlayerControlsConfiguration(
            updateFrequency: session.engine.updateFrequency,
            isPlaying: session.engine.isPlaying,
            currentTrackPosition: session.engine.currentTrackPosition,
            backForwardKind: backForwardKind)
    }
    
    
    /// Which back/forward buttons the player controls show for the current item: the skip-time buttons when the item is longer than `skipTimeMinimumDuration`, and the skip-track buttons when it is not.
    ///
    /// `nil` while the engine does not know the duration of the current item. The player controls then show no back/forward buttons.
    var backForwardKind: PlayerControlsConfiguration.BackForwardKind? {
        guard let duration = session.engine.duration else {
            return nil
        }
        
        if skipTimeMinimumDuration < duration {
            return .skipTime(forwardIncrement: skipTimeIncrement, backwardIncrement: skipTimeIncrement)
        }
        else {
            return .skipTrack
        }
    }
}



#Preview {
    ContentView()
}
