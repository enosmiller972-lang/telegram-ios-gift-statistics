import Foundation
import UIKit

/// With Increase Contrast on, raises the opacity of dim text until it reaches 4.5:1 on every given surface.
enum GiftStatsContrast {
    static let minimum: Double = 4.5

    /// Falls back to opaque `ink` or white, whichever contrasts better, when full opacity is still not enough.
    static func legible(_ ink: UIColor, over surfaces: [UIColor]) -> UIColor {
        guard GiftStatsEnvironment.increaseContrast, !surfaces.isEmpty else {
            return ink
        }
        func worst(_ color: UIColor) -> Double {
            return surfaces.map { GiftOKLab.contrast(color, over: $0) }.min() ?? 0.0
        }
        if worst(ink) >= self.minimum {
            return ink
        }
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var inkAlpha: CGFloat = 0.0
        ink.getRed(&red, green: &green, blue: &blue, alpha: &inkAlpha)
        var level = inkAlpha
        while level < 1.0 {
            level = min(1.0, level + 0.02)
            let candidate = UIColor(red: red, green: green, blue: blue, alpha: level)
            if worst(candidate) >= self.minimum {
                return candidate
            }
        }
        let solid = UIColor(red: red, green: green, blue: blue, alpha: 1.0)
        return worst(UIColor.white) > worst(solid) ? UIColor.white : solid
    }
}
