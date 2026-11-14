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
                metadataView
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
    
    /// The title and the artist of the loaded item
    var metadataView: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleView
                .font(.largeTitle.weight(.medium))
                .foregroundStyle(.primary) // not strictly necessary, but I wanted to explicitly call out the relationship to the next Text down
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
//                .border(.red)
            
            Text(creatorText)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize()
//                .border(.red)
            
            Spacer(minLength: 0)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
//        .border(.blue)
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



// MARK: - Metadata

private extension CustomMediaPlayer {
    
    /// The title of the loaded item. While something loads, this view shows `loadingMessage` and not the title.
    @ViewBuilder
    var titleView: some View {
        if let loadingMessage = session.loadingMessage {
            HStack {
                ProgressView()
                Text(LocalizedStringKey(loadingMessage.key))
                    .foregroundStyle(.secondary)
            }
        }
        else {
            Text({
                switch engine.metadata(.title) {
                case .none: nil == engine.currentItem ? "Pick something to play :3" : ""
                case .notStarted: "…"
                case .loading: "⋯"
                case .success(let value): "\(value)"
                case .failure(_): // If we ever add more possible error cases than NotFound, this needs updating
                    (engine.currentItem?.autoAccessSecurityScopedResourceUrl.deletingPathExtension().lastPathComponent.nonEmptyOrNil).map { "\($0)" } ?? "Untitled"
                }
            }())
        }
    }
    
    
    /// The artist of the loaded item, or an empty string while something loads
    var creatorText: LocalizedStringKey {
        guard nil == session.loadingMessage else { return "" }
        
        return switch engine.metadata(.creator) {
        case .none: ""
        case .notStarted: "⋯"
        case .loading: "…"
        case .success(let value): "\(value)"
        case .failure(_): ""
        }
    }
}



// MARK: - Previews

#Preview("Nothing playing") {
    NavigationStack {
        CustomMediaPlayer(session: PlayerSession(persisting: false))
    }
}
