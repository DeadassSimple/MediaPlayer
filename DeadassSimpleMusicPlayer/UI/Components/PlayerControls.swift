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



/// This view contains configurable controls for a media player, designed to appear in the same location on-screen at all times.
///
/// Apply this as a modifier to your view with ``.playerControls()``
private struct PlayerControls: View {
    
    let configuration: Configuration
    
    let onUserAction: OnUserAction
    
    
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass
    
    @State
    private var disabled: Bool = false
    
    
    @State
    private var screenCornerRadii: RectangleCornerRadii = Introspection.Device.current.dimensions.displayCornerRadii
    
    var body: some View {
        VStack {
            VStack {
                Spacer(minLength: minCornerRadius).fixedSize()
                
                Rectangle()
                    .fill(.accent)
                    .frame(height: 5)
            }
            .padding(12)
            
            Spacer(minLength: 0)//.fixedSize()
            Button(configuration.isPlaying ? "Pause" : "Play", systemImage: configuration.isPlaying ? "pause" : "play") {
                performUserAction(.play)
            }
            .disabled(disabled)
            .controlSize(.extraLarge).buttonBorderShape(.capsule).buttonStyle(.borderedProminent).labelsHidden()
            Spacer(minLength: 0)//.fixedSize()
        }
        .ignoresSafeArea(.container)
        .frame(height: 180)
//        .border(.red)
        .background {
            ConcentricRectangle(corners: .concentric(minimum: .fixed(minCornerRadius)))
                .fill(.background)
                .fill(.accent.opacity(0.1))
            //        .fill(.accent.opacity(0.03))
            //        .elevation(.z24)
        }
        .padding(inset)
        
//        .onGeometryChange(for: RectangleCornerRadii.self) { geometry in
//            if #available(anyAppleOS 27.0, *) {
//                geometry.concentricCornerRadii ?? .zero
//            } else {
//                Introspection.Device.current.dimensions.displayCornerRadii
//            }
//        }
//        action: { newValue in
//            screenCornerRadii = newValue
//        }
        .ignoresSafeArea(.container)
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



public struct PlayerControlsConfiguration {
    public var isPlaying: Bool = false
    public var backForwardKind: BackForwardKind = .skipTrack
    
    
    
    /// What kind of back/forward buttons should be in the player controls?
    public enum BackForwardKind {
        
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
        public let currentTime: Duration
        public let duration: Duration
    }
}



private struct PlayerControlsViewModifier: ViewModifier {
    
    let configuration: PlayerControlsConfiguration
    
    let onUserAction: PlayerAction.OnUserAction
    
    
    func body(content: Content) -> some View {
        content.overlay {
            VStack {
                Spacer()
                    .layoutPriority(2)
                
                PlayerControls(configuration: configuration, onUserAction: onUserAction)
                    .layoutPriority(1)
            }
//            .border(.blue)
            .ignoresSafeArea()
        }
    }
}



public extension View {
    func playerControls(configuration: PlayerControlsConfiguration, onUserAction: @escaping PlayerAction.OnUserAction) -> some View {
        modifier(PlayerControlsViewModifier(configuration: configuration, onUserAction: onUserAction))
    }
}



#Preview {
    Rectangle().fill(.background)
        .playerControls(configuration: .init(isPlaying: false, backForwardKind: .skipTrack), onUserAction: null)
}
