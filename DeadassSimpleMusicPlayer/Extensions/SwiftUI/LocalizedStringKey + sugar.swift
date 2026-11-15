//
//  LocalizedStringKey + sugar.swift
//  Dead-Simple Media Player
//
//  Created by Ky on 2026-11-15.
//

import SwiftUI



public extension LocalizedStringKey {
    init(_ resource: LocalizedStringResource) {
        self.init(resource.key)
    }
}
