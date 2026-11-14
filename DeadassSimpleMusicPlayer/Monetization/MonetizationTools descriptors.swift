//
//  MonetizationTools descriptors.swift
//  Dead-Simple Media Player
//
//  Created by Ky on 2026-09-21.
//

import Foundation

import MonetizationTools



// MARK: - Tip jar

extension MonetizationPromptIdentifier {
    static let tipJar: Self = "org.bhstudios.dsmp.tipjar.20260923"
    static let license: Self = "org.bhstudios.dsmp.license.20260925"
}



extension MonetizationPrompt.Descriptor {
    static let tipJar = Self(.tipJar, atMost: .weekly, scope: .perApp, action: .storeKitPurchase)
    static let license = Self(.license, atMost: .quarterly, scope: .perApp, action: .storeKitPurchase)
}
