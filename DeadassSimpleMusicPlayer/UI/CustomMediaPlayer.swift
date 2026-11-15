//
//  CustomMediaPlayer.swift
//  DeadassSimpleMusicPlayer
//
//  Created by Ky on 2024-06-08.
//

import SwiftUI

import CollectionTools
import SimpleLogging



/// Shows the media of a `PlayerSession`, with the title and the artist below it.
///
/// Use this view when your app owns a `PlayerSession`, for example to keep a queue, a history and a library. To play files without a session of your own, use `MediaPlayer`.
///
/// This view keeps no playback state. It shows the `PlaybackEngine` of the session. Thus other views (for example, a metadata header or a transport bar) can read and control the same engine at the same time.
struct CustomMediaPlayer: View {
    
    /// Part of the layout decision in `useFullscreenUi`. At this time, the layout does not change with the width.
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass
    
    /// Selects the layout: a compact height shows the media full screen, with no title or artist
    @Environment(\.verticalSizeClass)
    private var verticalSizeClass
    
    // MARK: API
    
    /// The session that this view shows. The caller owns the session. When the caller gives a different session, this view shows the new session.
    let session: PlayerSession
    
    
    // MARK: Private state
    
    /// The picture-in-picture state of the player
    @State
    private var pipStatus = Player.PipStatus.undefined
    
    
    /// Shows the media of `session`
    /// - Parameter session: The session to show. Its engine plays the media, and its queue selects the media.
    init(session: PlayerSession) {
        self.session = session
    }
    
    
    // MARK: `View`
    
    var body: some View {
        VStack {
            playerView
            
            if !useFullscreenUi {
                TitleBar(mode: titleBarMode)
            }
        }
        .background(Color(.secondarySystemBackground))
        .background(ignoresSafeAreaEdges: .all)
    }
}



private extension CustomMediaPlayer {
    
    /// The engine of `session`
    var engine: PlaybackEngine {
        session.engine
    }
    
    
    /// `true` when the media fills the screen with no title or artist, which is when the height is compact
    var useFullscreenUi: Bool {
        switch (width: horizontalSizeClass, height: verticalSizeClass) {
        case (width: _, height: .none),
            (width: _, height: .regular):
            false
            
        case (width: _, height: .compact):
            true
            
        @unknown default:
            false
        }
    }
}



// MARK: - Subviews

private extension CustomMediaPlayer {
    
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
    
    
    /// The media itself: the video, or the cover art for audio
    var playerView: some View {
        Player(player: engine.player, artwork: engine.artwork, pipStatus: $pipStatus)
            .aspectRatio(16/9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .layoutPriority(2)
            .ignoresSafeArea(.container, edges: useFullscreenUi ? .top : [])
    }
}




// MARK: - Previews

#Preview("Nothing playing") {
    NavigationStack {
        CustomMediaPlayer(session: PlayerSession(persisting: false))
    }
}
