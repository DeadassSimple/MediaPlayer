//
//  UI constants.swift
//  DeadassSimpleMusicPlayer
//
//  Created by Ky on 2026-11-12.
//

import Foundation



/// How many points wide each pixel in pixelart is by default
@inline(__always)
internal let pixelSize: CGFloat = 3



/// Converts the given number of pixelart pixels into a number of display points
///
/// This uses the current ``pixelSize`` to determine the size of the pixels in the pixel art
///
/// - Parameter pixelCount: The measure of pixels in pixelart
/// - Returns: The measure of pixelart pixels in display points. For example, if the pixelart's pixels are each 3pt squares, then `pixels(4)` returns `12.0` points.
@inline(__always)
internal func pixels<PixelCount: BinaryInteger>(_ pixelCount: PixelCount) -> CGFloat {
    .init(pixelCount) * pixelSize
}



/// Converts the given number of pixelart pixels into a number of display points
///
/// This uses the current ``pixelSize`` to determine the size of the pixels in the pixel art
///
/// - Parameter pixelCount: The measure of pixels in pixelart
/// - Returns: The measure of pixelart pixels in display points. For example, if the pixelart's pixels are each 3pt squares, then `pixels(4)` returns `12.0` points.
@inline(__always)
internal func pixels<PixelCount: BinaryFloatingPoint>(_ pixelCount: PixelCount) -> CGFloat {
    .init(pixelCount) * pixelSize
}
