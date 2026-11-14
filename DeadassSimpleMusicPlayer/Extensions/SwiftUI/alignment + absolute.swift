//
//  alignment + absolute.swift
//  DeadassSimpleMusicPlayer
//
//  Created by Ky on 2026-11-09.
//

import SwiftUI



public extension Alignment {
    
    /// Align center-left, regardless of the current layout direction.
    ///
    /// SwiftUI lays out components differently depending on the current layout direction.
    /// For that reason, SwiftUI only provides `.leading`/`.trailing` for horizontal alignment, but not `.left`/`.right`.
    /// For that reason, this takes the current layout direction, and returns `.leading` or `.trailing` depending on which one the given layout direction treats as "left".
    ///
    /// - Parameter layoutDirection: The current layout direction (e.g. as you would get from `@Environment(\.layoutDirection)`.
    ///
    /// - Returns: A vertically-centered leftward horizontal alignment
    static func left(in layoutDirection: LayoutDirection) -> Self {
        .init(horizontal: .left(in: layoutDirection), vertical: .center)
    }
    
    
    static func right(in layoutDirection: LayoutDirection) -> Self {
        .init(horizontal: .right(in: layoutDirection), vertical: .center)
    }
    
    
    /// Align top-left, regardless of the current layout direction.
    ///
    /// SwiftUI lays out components differently depending on the current layout direction.
    /// For that reason, SwiftUI only provides `.leading`/`.trailing` for horizontal alignment, but not `.left`/`.right`.
    /// For that reason, this takes the current layout direction, and returns `.leading` or `.trailing` depending on which one the given layout direction treats as "left".
    ///
    /// - Parameter layoutDirection: The current layout direction (e.g. as you would get from `@Environment(\.layoutDirection)`.
    ///
    /// - Returns: An upward leftward horizontal alignment
    static func topLeft(in layoutDirection: LayoutDirection) -> Self {
        .init(horizontal: .left(in: layoutDirection), vertical: .top)
    }
    
    
    static func topRight(in layoutDirection: LayoutDirection) -> Self {
        .init(horizontal: .right(in: layoutDirection), vertical: .top)
    }
    
    
    static func bottomLeft(in layoutDirection: LayoutDirection) -> Self {
        .init(horizontal: .left(in: layoutDirection), vertical: .bottom)
    }
    
    
    static func bottomRight(in layoutDirection: LayoutDirection) -> Self {
        .init(horizontal: .right(in: layoutDirection), vertical: .bottom)
    }
}



public extension HorizontalAlignment {
    
    /// Align left, regardless of the current layout direction.
    ///
    /// SwiftUI lays out components differently depending on the current layout direction.
    /// For that reason, SwiftUI only provides `.leading`/`.trailing` for horizontal alignment, but not `.left`/`.right`.
    /// For that reason, this takes the current layout direction, and returns `.leading` or `.trailing` depending on which one the given layout direction treats as "left".
    ///
    /// - Parameter layoutDirection: The current layout direction (e.g. as you would get from `@Environment(\.layoutDirection)`.
    ///
    /// - Returns: A leftward horizontal alignment
    static func left(in layoutDirection: LayoutDirection) -> Self {
        switch layoutDirection {
        case .leftToRight: .leading
        case .rightToLeft: .trailing
        @unknown default:  .leading
        }
    }
    
    
    /// Align right, regardless of the current layout direction.
    ///
    /// SwiftUI lays out components differently depending on the current layout direction.
    /// For that reason, SwiftUI only provides `.leading`/`.trailing` for horizontal alignment, but not `.left`/`.right`.
    /// For that reason, this takes the current layout direction, and returns `.leading` or `.trailing` depending on which one the given layout direction treats as "right".
    ///
    /// - Parameter layoutDirection: The current layout direction (e.g. as you would get from `@Environment(\.layoutDirection)`.
    ///
    /// - Returns: A rightward horizontal alignment
    static func right(in layoutDirection: LayoutDirection) -> Self {
        switch layoutDirection {
        case .leftToRight: .trailing
        case .rightToLeft: .leading
        @unknown default:  .trailing
        }
    }
}
