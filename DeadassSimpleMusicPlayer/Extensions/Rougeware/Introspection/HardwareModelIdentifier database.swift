//
//  HardwareModelIdentifier database.swift
//  Dead-Simple Media Player
//
//  Created by Ky on 2026-10-06.
//

import Foundation

import Introspection



public extension Introspection.Device.HardwareModelIdentifier {
    static var iPhone_14pm: Self { .init(type: .iPhone, version: .init(major: 15, minor: 3)) }
    static var iPhone_15pm: Self { .init(type: .iPhone, version: .init(major: 16, minor: 2)) }
    static var iPhone_Duo: Self { .init(type: .iPhone, version: .init(major: 19, minor: 4)) }
}
