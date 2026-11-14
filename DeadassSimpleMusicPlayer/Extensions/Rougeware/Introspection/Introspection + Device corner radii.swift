//
//  Introspection + Device corner radii.swift
//  Dead-Simple Media Player
//
//  Created by Ky on 2026-10-06.
//

import Foundation

import Introspection
import RectangleTools

#if canImport(SwiftUI)
import SwiftUI



public extension Introspection.Device {
    var dimensions: Dimensions {
        switch self.hardwareModelIdentifier {
        case .iPhone_15pm, .iPhone_14pm:
                .init(displayCornerRadii: .init(55))
            
        case .iPhone_Duo:
                .init(displayCornerRadii: .init(55),
                      outerDisplayCornerRadii: .init(
                        topLeading: 8,
                        bottomLeading: 8,
                        bottomTrailing: 59,
                        topTrailing: 59,
                      )
                )
            
        default:
                .init(displayCornerRadii: .init(8))
        }
    }
}



public extension Introspection.Device {
    struct Dimensions {
        let displayCornerRadii: RectangleCornerRadii
        let outerDisplayCornerRadii: RectangleCornerRadii?
        
        
        init(
            displayCornerRadii: RectangleCornerRadii,
            outerDisplayCornerRadii: RectangleCornerRadii? = nil,
        ) {
            self.displayCornerRadii = displayCornerRadii
            self.outerDisplayCornerRadii = outerDisplayCornerRadii
        }
    }
}
#endif
