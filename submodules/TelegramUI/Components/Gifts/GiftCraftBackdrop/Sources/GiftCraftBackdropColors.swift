import Foundation
import UIKit
import Display

public struct GiftCraftBackdropColors: Equatable {
    public let top: UIColor
    public let bottom: UIColor
    public let glow: UIColor
    public let tint: UIColor

    public init(top: UIColor, bottom: UIColor, glow: UIColor, tint: UIColor) {
        self.top = top
        self.bottom = bottom
        self.glow = glow
        self.tint = tint
    }

    public static let standard = GiftCraftBackdropColors(top: UIColor(rgb: 0x263245), bottom: UIColor(rgb: 0x232e3f), glow: UIColor(rgb: 0x304059), tint: UIColor(rgb: 0x425168))
    public static let success = GiftCraftBackdropColors(top: UIColor(rgb: 0x1b3b3d), bottom: UIColor(rgb: 0x1a2f38), glow: UIColor(rgb: 0x22464a), tint: UIColor(rgb: 0x2d4e50))
    public static let failure = GiftCraftBackdropColors(top: UIColor(rgb: 0x46231a), bottom: UIColor(rgb: 0x381b1a), glow: UIColor(rgb: 0x51291f), tint: UIColor(rgb: 0x683e34))
}
