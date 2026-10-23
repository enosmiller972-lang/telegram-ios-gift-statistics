import Foundation
import UIKit
import Display
import TelegramCore
import GiftStats

/// Flat tonal surface definition for statistics tiles and controls.
public struct GiftStatsTileSurface: Equatable {
    public var flat: GiftFlat
}

/// Shared style constants for collectible sheet controls and statistics tiles.
public enum GiftStatsTileStyle {
    public enum Shape {
        case tile
        case capsule
    }

    public static let height: CGFloat = 58.0
    public static let spacing: CGFloat = 10.0
    public static let radius: CGFloat = 16.0
    /// Where the middle of the icon (or of the number) and of the label are, from the top of the tile.
    public static let iconCenterY: CGFloat = 22.0
    public static let labelCenterY: CGFloat = 42.0
    public static let labelFont = Font.regular(11.0)
    public static let iconColor = UIColor.white
    public static let labelColor = UIColor(white: 1.0, alpha: 0.85)

    public static func surface(palette: GiftTonalPalette) -> GiftStatsTileSurface {
        return GiftStatsTileSurface(flat: palette.surface)
    }

    /// Tile surface for a specific unique gift's palette.
    public static func surface(gift: StarGift.UniqueGift, outerShare: CGFloat = 1.0) -> GiftStatsTileSurface {
        let palette = GiftTonalPalette.cached(gift: gift)
        return GiftStatsTileSurface(flat: palette.surface(outerShare: outerShare))
    }
}
