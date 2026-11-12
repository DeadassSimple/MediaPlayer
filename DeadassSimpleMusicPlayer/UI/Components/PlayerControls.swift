//
//  PlayerControls.swift
//  Dead-Simple Media Player
//
//  Created by Ky on 2026-10-06.
//

import SwiftUI

import FunctionTools
import Introspection



private let inset: CGFloat = 4
private let minCornerRadius: CGFloat = 24
private let ignoredSafeAreaEdges: Edge.Set = .bottom

private let buttonSize_large: CGFloat = 78
private let buttonSize_regular: CGFloat = 72

private let playheadHeight: CGFloat = 8 * pixelSize
private let playheadVerticalOffset: CGFloat = 7 * pixelSize



/// This view contains configurable controls for a media player, designed to appear in the same location on-screen at all times.
///
/// Apply this as a modifier to your view with ``.playerControls()``
private struct PlayerControls: View {
    
    let configuration: Configuration
    
    let onUserAction: OnUserAction
    
    
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass
    
    @Environment(\.layoutDirection)
    private var layoutDirection
    
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    
    @State
    private var disabled: Bool = false
    
    @State
    private var screenCornerRadii: RectangleCornerRadii = Introspection.Device.current.dimensions.displayCornerRadii
    
    @State
    private var scrubBarWidth: CGFloat = 0
    
    
    @GestureState(resetTransaction: Transaction(animation: .bouncy))
    private var scrubSession: ScrubSession? = nil
    
    
    var body: some View {
        VStack {
            VStack {
                Spacer(minLength: minCornerRadius).fixedSize()
                
                scrubBar
            }
            .padding(12)
            
            Spacer(minLength: 0)
            transportButtons
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.accentColor)
        .flipsForRightToLeftLayoutDirection(false)
        .ignoresSafeArea(.container, edges: ignoredSafeAreaEdges)
        
        .background {
            ConcentricRectangle(corners: .concentric(minimum: .fixed(minCornerRadius)))
                .fill(.background)
                .fill(.accent.opacity(0.1))
                .materialShadow(.z24)
        }
        .padding(inset)
        
        .ignoresSafeArea(.container, edges: ignoredSafeAreaEdges)
        .disabled(nil == configuration.currentTrackPosition)
    }
    
    
    
    private func performUserAction(_ action: PlayerAction) {
        Task { @UserActionQueue in
            await MainActor.run { disabled = true }
            defer { await MainActor.run { disabled = false } }
            await onUserAction(action)
        }
    }
    
    
    
    typealias Configuration = PlayerControlsConfiguration
    typealias OnUserAction = PlayerAction.OnUserAction
}



@globalActor
final actor UserActionQueue: GlobalActor {
    public static let shared = ActorType()
    public typealias ActorType = UserActionQueue
}



// MARK: - Scrub bar

private extension PlayerControls {
    
    var scrubBar: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .left(in: layoutDirection)) {
                scrubBarBackground
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { scrubBarWidth = $0 }
                
                scrubBarForeground
                    .overlay(alignment: .trailing) {
                        if nil != scrubSession {
                            VStack {
                                Image(.TransportControls.playhead)
                            }
                            .offset(x: 2.5 * pixelSize, y: -(playheadVerticalOffset + playheadHeight))
//                            .drawingGroup()
                            .transition(
                                .asymmetric(
                                    insertion:
                                            .offset(y: playheadVerticalOffset)
//                                            .combined(with: .opacity)
                                            .animation(.bouncy)
                                    ,
                                    removal:
                                            .offset(y: playheadVerticalOffset)
                                            .animation(.bouncy)
                                    ,
                                )
                                .combined(with: .opacity)
                            )
                        }
                    }
            }
            .frame(height: 4 * pixelSize)
            .animation(.linear(duration: configuration.updateFrequency), value: configuration)


            HStack {
                Text(currentTrackTimestamp).multilineTextAlignment(.leading)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2),
                               value: configuration.currentTrackPosition?.current)
                    .transition(.opacity.animation(.smooth))
                Spacer()
                Text(currentTrackTotalTimestamp).multilineTextAlignment(.trailing)
                    .transition(.opacity.animation(.smooth))
            }
            .font(.system(size: 24, weight: .black, design: .rounded))
            .opacity(nil == configuration.currentTrackPosition ? 0 : 1)
        }
        .gesture(scrubGesture)
        .onChange(of: scrubSession) { oldSession, newSession in
            if let oldSession, nil == newSession {
                // A scrub session just ended. Send a `.complete`.
                performUserAction(.scrub(transaction: .init(
                    id: oldSession.id,
                    startPosition: oldSession.startPosition,
                    currentPosition: oldSession.currentPosition.map { .setPlayhead(to: $0) } ?? .makeNoChange,
                    wasPlayingAtStart: oldSession.wasPlayingAtStart,
                    phase: .complete,
                )))
            }
        }
    }
    
    
    private var scrubBarForeground: some View {
        Rectangle()
            .fill(.accent)
            .relativeProposed(width: currentTrackPercent)
    }
    
    
    private var scrubBarBackground: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.2))
    }
}



private extension PlayerControls {
    var currentTrackPercent: CGFloat {
        guard let currentTrackPosition = configuration.currentTrackPosition,
              currentTrackPosition.total > .zero
        else {
            return 0
        }
        
        return currentTrackPosition.current / currentTrackPosition.total
    }
    
    
    var currentTrackTimestamp: String {
        configuration.currentTrackPosition?.current.mediaPositionTimestamp ?? ""
    }
    
    
    var currentTrackTotalTimestamp: String {
        configuration.currentTrackPosition?.total.mediaPositionTimestamp ?? "🫪"
    }
}



private extension PlayerControls {
    
    var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($scrubSession) { value, inoutScrubSession, transaction in
                defer { inoutScrubSession?.phase = .ongoing }
                transaction.animation = .bouncy
                
                let _temp_scrubSession: ScrubSession
                if let inoutScrubSession {
                    _temp_scrubSession = inoutScrubSession
                }
                else {
                    _temp_scrubSession = ScrubSession(
                        startPosition: configuration.currentTrackPosition?.current ?? .zero,
                        wasPlayingAtStart: configuration.isPlaying,
                        phase: .starting,
                    )
                    inoutScrubSession = _temp_scrubSession
                }
                
                let currentPosition = scrubPosition(movedBy: value.translation.width, from: _temp_scrubSession.startPosition)
                inoutScrubSession?.currentPosition = currentPosition
                
                guard let currentPosition else {
                    performUserAction(.scrub(transaction: .init(
                        id: _temp_scrubSession.id,
                        startPosition: _temp_scrubSession.startPosition,
                        currentPosition: .makeNoChange,
                        wasPlayingAtStart: _temp_scrubSession.wasPlayingAtStart,
                        phase: _temp_scrubSession.phase,
                    )))
                    return
                }
                
                performUserAction(.scrub(transaction: .init(
                    id: _temp_scrubSession.id,
                    startPosition: _temp_scrubSession.startPosition,
                    currentPosition: .setPlayhead(to: currentPosition),
                    wasPlayingAtStart: _temp_scrubSession.wasPlayingAtStart,
                    phase: _temp_scrubSession.phase,
                )))
            }
    }
    
    
    /// The playhead position after the finger moves `distance` points along the scrub bar, starting from `startPosition`, or `nil` when no position is known
    func scrubPosition(movedBy distance: CGFloat, from startPosition: Duration) -> Duration? {
        guard let total = configuration.currentTrackPosition?.total,
              0 < scrubBarWidth
                else {
            return nil
        }
        
        let position = startPosition + (total * (distance / scrubBarWidth))
        return min(max(position, .zero), total)
    }
}



// MARK: - Transport controls

private extension PlayerControls {
    var transportButtons: some View {
        HStack {
            backButton
                .transition(.opacity.animation(.smooth))
            
            Spacer(minLength: 32).fixedSize()
            
            playPauseButton
                .transition(.opacity.animation(.smooth))
            
            Spacer(minLength: 32).fixedSize()
            
            forwardButton
                .transition(.opacity.animation(.smooth))
        }
        .disabled(disabled)
    }
    
    
    var playPauseButton: some View {
        transportButton(
            action: configuration.isPlaying ? .pause : .play,
            imageName: configuration.isPlaying ? .TransportControls.pause : .TransportControls.play,
            size: buttonSize_large
        )
    }
    
    
    @ViewBuilder
    var backButton: some View {
        switch configuration.backForwardKind {
        case .skipTrack:
            previousTrackButton
            
        case .skipTime(forwardIncrement: _, backwardIncrement: let increment):
            skipBackButton(increment: increment)
            
        case nil:
            previousTrackButton
                .disabled(true)
                .opacity(0)
        }
    }
    
    
    @ViewBuilder
    var forwardButton: some View {
        switch configuration.backForwardKind {
        case .skipTrack:
            nextTrackButton
            
        case .skipTime(forwardIncrement: _, backwardIncrement: let increment):
            skipForwardButton(increment: increment)
            
        case nil:
            nextTrackButton
                .disabled(true)
                .opacity(0)
        }
    }
    
    
    var previousTrackButton: some View {
        transportButton(action: .previousTrack, imageName: .TransportControls.previousTrack)
    }
    
    
    var nextTrackButton: some View {
        transportButton(action: .nextTrack, imageName: .TransportControls.nextTrack)
    }
    
    
    func skipBackButton(increment: PlayerAction.SkipIncrement) -> some View {
        transportButton(
            action: .skipBackward(increment: increment),
            imageName: .TransportControls.skipBack,
            overlayText: increment.overlayText
        )
    }
    
    
    func skipForwardButton(increment: PlayerAction.SkipIncrement) -> some View {
        transportButton(
            action: .skipForward(increment: increment),
            imageName: .TransportControls.skipForward,
            overlayText: increment.overlayText
        )
    }
    
    
    private func transportButton(
        action: PlayerAction,
        imageName: ImageResource,
        size: CGFloat = buttonSize_regular,
    ) -> some View {
        CustomIconButton(icon: imageName, iconSize: .square(size)) {
            performUserAction(action)
        }
    }
    
    
    private func transportButton(
        action: PlayerAction,
        imageName: ImageResource,
        size: CGFloat = buttonSize_regular,
        overlayText: LocalizedStringKey,
    ) -> some View {
        ZStack {
            transportButton(
                action: action,
                imageName: imageName,
                size: size,
            )
            
            Text(overlayText)
                .font(.system(size: size/3, weight: .black, design: .rounded))
                .foregroundStyle(.brand)
                .multilineTextAlignment(.center)
                .padding(.top, imageName.verticalPixelOffsetForCenteredText * pixelSize)
        }
    }
}



private extension Duration {
    var overlayText: LocalizedStringKey {
        "\(UInt(abs(timeInterval.rounded())))"
    }
}



private extension ImageResource {
    var verticalPixelOffsetForCenteredText: CGFloat {
        switch self {
        case .TransportControls.skipBack,
                .TransportControls.skipForward:
            return 2
            
        default:
            return 0
        }
    }
}



// MARK: - Supporting types

/// Describes the current state of player controls
public struct PlayerControlsConfiguration: Sendable, Equatable {
    
    /// How many times per second the player controls should be expected to update to reflect the player
    public var updateFrequency: TimeInterval
    
    /// `true` iff the current media is currently playing
    public var isPlaying: Bool = false
    
    /// How much of the current media has been played
    public var currentTrackPosition: PlayheadPosition?
    
    /// What kind of back/forward buttons the controls should use. `nil` hides the back/forward buttons
    public var backForwardKind: BackForwardKind? = .skipTrack
    
    
    
    /// What kind of back/forward buttons should be in the player controls?
    public enum BackForwardKind: Sendable, Equatable {
        
        /// Skip back/forward by a certain duration
        case skipTime(forwardIncrement: SkipIncrement, backwardIncrement: SkipIncrement)
        
        /// Skip to the previous/next track
        case skipTrack
        
        
        
        public typealias SkipIncrement = PlayerAction.SkipIncrement
    }
}



public enum PlayerAction: Sendable {
    case previousTrack
    case nextTrack
    
    case skipBackward(increment: SkipIncrement)
    case skipForward(increment: SkipIncrement)
    
    case reverse(transaction: TransportTransaction)
    case fastForward(transaction: TransportTransaction)
    
    case scrub(transaction: TransportTransaction)
    
    case play
    case pause
    
    
    
    public typealias SkipIncrement = Duration
    
    public typealias OnUserAction = @Sendable (PlayerAction) async -> Void
    
    
    
    /// Describes the state of a transport action, such as scrubbing or fast-forwarding
    public struct TransportTransaction: Sendable, Identifiable {
        public let id: UUID
        
        /// The playhead position when the transaction started
        public let startPosition: Duration
        
        /// The current position that the user wants the playhead
        public let currentPosition: UserPosition
        
        /// Whether the player was actively playing an item when the transaction started
        public let wasPlayingAtStart: Bool
        
        /// The current phase of this transaction update
        public let phase: Phase
        
        
        
        /// Where the user , in a transport transaction
        public enum UserPosition: Sendable, Equatable {
            
            /// The user wants to move the playhead to this specific moment
            case setPlayhead(to: Duration)
            
            /// The user does not want to make a change (e.g. is cancelling an existing seek)
            case makeNoChange
        }
        
        
        
        public enum Phase: Sendable, Equatable {
            
            /// This is the first update in this transaction
            case starting
            
            /// The transaction is ongoing; this update is a normal update in the middle of the transaction
            case ongoing
            
            /// No further updates will be sent for this transaction, and all other fields indicate the user's final desired state
            case complete
        }
    }
}



private struct PlayerControlsViewModifier: ViewModifier {
    
    let configuration: PlayerControlsConfiguration
    
    let onUserAction: PlayerAction.OnUserAction
    
    
    func body(content: Content) -> some View {
        content.overlay {
            VStack {
                Spacer(minLength: 144).allowsHitTesting(false)
                    .layoutPriority(2)

                PlayerControls(configuration: configuration, onUserAction: onUserAction)
                    .frame(minHeight: 292)
                    .layoutPriority(0)
            }
//            .border(.blue)
            .ignoresSafeArea(edges: ignoredSafeAreaEdges)
        }
    }
}



/// The state of a user's session of scrubbing through the current item to find where they want the palyhead
private struct ScrubSession: Equatable, Identifiable {
    
    /// Uniquely identifiers the scrubbing session
    let id = UUID()
    
    /// Where in the item the playhead sat before the user started scrubbing
    let startPosition: Duration
    
    /// Whether the item was playing when the user started scrubbing
    let wasPlayingAtStart: Bool
    
    /// Where in the item the playhead sits as the user is currently scrubbing.
    ///
    /// `nil` indicates that the user wishes to cancel the scrubbing
    var currentPosition: Duration?
    
    /// The current phase of the transport action that this scrub session takes place within
    var phase: PlayerAction.TransportTransaction.Phase
}



// MARK: - Previews

public extension View {
    func playerControls(configuration: PlayerControlsConfiguration, onUserAction: @escaping PlayerAction.OnUserAction) -> some View {
        modifier(PlayerControlsViewModifier(configuration: configuration, onUserAction: onUserAction))
    }
}



private let __preview_total = Duration.seconds((3 * 60) + 45)
private let __preview_trackPosition_early = PlayheadPosition(current: .seconds(4), total: __preview_total)
private let __preview_trackPosition_mid = PlayheadPosition(current: .seconds((2 * 60) + 22), total: __preview_total)
private let __preview_trackPosition_late = PlayheadPosition(current: .seconds((3 * 60) + 43), total: __preview_total)



#Preview("Paused music") {
    Rectangle().fill(.background)
        .playerControls(configuration: .init(
            updateFrequency: 0,
            isPlaying: false,
            currentTrackPosition: nil,
            backForwardKind: .skipTrack,
        ), onUserAction: null)
}


#Preview("Playing podcast") {
    Rectangle().fill(.background)
        .playerControls(configuration: .init(
            updateFrequency: 0,
            isPlaying: true,
            currentTrackPosition: __preview_trackPosition_mid,
            backForwardKind: .skipTime(forwardIncrement: .seconds(15), backwardIncrement: .seconds(15)),
        ), onUserAction: null)
}
