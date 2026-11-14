//
//  RectangleCornerRadii + sugar.swift
//  Dead-Simple Media Player
//
//  Created by Ky on 2026-11-01.
//

import Foundation



#if canImport(SwiftUI)
import SwiftUI



public extension RectangleCornerRadii {
    init(_ radius: CGFloat) {
        self.init(
            topLeading: radius,
            bottomLeading: radius,
            bottomTrailing: radius,
            topTrailing: radius,
        )
    }
    
    
    init(leading: CGFloat, trailing: CGFloat) {
        self.init(
            topLeading: leading,
            bottomLeading: leading,
            bottomTrailing: trailing,
            topTrailing: trailing,
        )
    }
}
#endif
