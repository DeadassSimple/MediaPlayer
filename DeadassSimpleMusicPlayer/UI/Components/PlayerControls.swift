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
    }
    
    
    
    private func performUserAction(_ action: PlayerAction) {
        Task {
            disabled = true
            await onUserAction(action)
            disabled = false
        }
    }
    
    
    
    typealias Configuration = PlayerControlsConfiguration
    typealias OnUserAction = PlayerAction.OnUserAction
}



// MARK: - Scrub bar

private extension PlayerControls {
    
    var scrubBar: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .left(in: layoutDirection)) {
                scrubBarBackground
                
                scrubBarForeground
            }
            .frame(height: 4 * 3)
            .animation(.linear(duration: configuration.updateFrequency), value: configuration)
            
            HStack {
                Text(currentTrackTimestamp).multilineTextAlignment(.leading)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2),
                               value: configuration.currentTrackPosition?.current)
                Spacer()
                Text(currentTrackTotalTimestamp).multilineTextAlignment(.trailing)
            }
            .font(.system(size: 24, weight: .black, design: .rounded))
            .opacity(nil == configuration.currentTrackPosition ? 0 : 1)
        }
    }
    
    
    private var scrubBarForeground: some View {
        Rectangle()
            .fill(.accent)
//            .containerRelativeFrame(.horizontal, alignment: .left(in: layoutDirection)) { length, _ in
//                length * currentTrackPercent
//            }
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



// MARK: - Transport controls

private extension PlayerControls {
    var transportButtons: some View {
        HStack {
            backButton
            
            Spacer(minLength: 32).fixedSize()
            
            playPauseButton
            
            Spacer(minLength: 32).fixedSize()
            
            forwardButton
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
        }
    }
    
    
    @ViewBuilder
    var forwardButton: some View {
        switch configuration.backForwardKind {
        case .skipTrack:
            nextTrackButton
            
        case .skipTime(forwardIncrement: _, backwardIncrement: let increment):
            skipForwardButton(increment: increment)
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
        Button {
            performUserAction(action)
        } label: {
            Image(imageName)
                .resizable()
                .frame(width: size, height: size)
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
                .padding(.top, imageName.verticalPixelOffsetForCenteredText * 3)
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
    
    /// What kind of back/forward buttons the controls should use
    public var backForwardKind: BackForwardKind = .skipTrack
    
    
    
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
    
    
    
    public struct TransportTransaction: Sendable {
        public let transactionId: UUID
        public let startPosition: Duration
        public let currentPosition: Duration
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



public extension View {
    func playerControls(configuration: PlayerControlsConfiguration, onUserAction: @escaping PlayerAction.OnUserAction) -> some View {
        modifier(PlayerControlsViewModifier(configuration: configuration, onUserAction: onUserAction))
    }
}



private let __preview_trackPosition_early = PlayheadPosition(current: .seconds(4), total: .seconds((3 * 60) + 45))
private let __preview_trackPosition_late = PlayheadPosition(current: .seconds((3 * 60) + 43), total: .seconds((3 * 60) + 45))



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
            currentTrackPosition: __preview_trackPosition_late,
            backForwardKind: .skipTime(forwardIncrement: .seconds(15), backwardIncrement: .seconds(15)),
        ), onUserAction: null)
}
