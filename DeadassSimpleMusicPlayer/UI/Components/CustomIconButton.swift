//
//  CustomIconButton.swift
//  DeadassSimpleMusicPlayer
//
//  Created by Ky on 2026-11-10.
//

import SwiftUI



public struct CustomIconButton: View {
    
    @Environment(\.isEnabled)
    private var isEnabled
    
    
    private let icon: Image
    
    private let iconSize: CGSize
    
    private let action: () -> Void
    
    
    public var body: some View {
        Button(action: action, label: {
            icon
                .resizable()
                .frame(width: iconSize.width, height: iconSize.height)
                .opacity(isEnabled ? 1 : 0.2)
        })
    }
}



public extension CustomIconButton {
    init(
        icon imageResource: ImageResource,
        iconSize: CGSize,
        action: @escaping () -> Void)
    {
        self.init(
            icon: .init(imageResource),
            iconSize: iconSize,
            action: action,
        )
    }
}
