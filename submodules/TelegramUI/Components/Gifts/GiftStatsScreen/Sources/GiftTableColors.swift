import Foundation
import UIKit

public struct GiftTableColors {
    public let panel: UIColor
    public let separator: UIColor
    public let label: UIColor
}

public extension GiftTonalPalette {
    internal static let tableShare: CGFloat = 0.75
    // Minimum OKLab lightness gap between the panel and the backdrop.
    internal static let tableSeparation: Double = 0.05
    internal static let lightBackdrop: Double = 0.60
    internal static let lightValueContrast: Double = 3.5

    // The panel moves tableShare toward the backdrop, backing off while labels or white values would drop below
    // 3:1 / 4.5:1 (or the tonal panel's own contrast if lower). Light backdrops use lightTable.
    var table: GiftTableColors {
        guard let backdrop = self.backdropBehindTable else {
            return GiftTableColors(panel: self.panel, separator: self.separator, label: self.label)
        }
        if let light = self.lightTable(backdrop: backdrop) {
            return light
        }
        let minimum = GiftStatsEnvironment.increaseContrast ? 4.5 : 3.0
        let ink = self.label.withAlphaComponent(1.0)
        let labelNeed = min(minimum, GiftOKLab.contrast(ink, over: self.panel))
        let valueNeed = min(4.5, GiftOKLab.contrast(.white, over: self.panel))
        var share = GiftTonalPalette.tableShare
        while share > 0.0 {
            let panel = self.separated(mix: share, from: backdrop)
            if GiftOKLab.contrast(ink, over: panel) >= labelNeed && GiftOKLab.contrast(.white, over: panel) >= valueNeed {
                break
            }
            share -= 0.025
        }
        guard share > 0.0 else {
            return GiftTableColors(panel: self.panel, separator: self.separator, label: self.label)
        }
        let panel = self.separated(mix: share, from: backdrop)
        var alpha = self.label.cgColor.alpha
        while alpha < 1.0 && GiftOKLab.contrast(ink.withAlphaComponent(alpha), over: panel) < labelNeed {
            alpha = min(1.0, alpha + 0.02)
        }
        return GiftTableColors(panel: panel, separator: panel.mixedOKLab(with: .white, alpha: 0.12), label: ink.withAlphaComponent(alpha))
    }

    internal func separated(mix share: CGFloat, from backdrop: UIColor) -> UIColor {
        let mixed = self.panel.mixedOKLab(with: backdrop, alpha: share)
        let nearLightness = backdrop.oklab.l
        let lighter = self.panel.oklab.l >= nearLightness
        // The backdrop is a gradient behind the table; stay separated from both ends.
        let farLightness = self.backdropOuterForTable?.oklab.l ?? nearLightness
        let backdropLightness = lighter ? max(nearLightness, farLightness) : min(nearLightness, farLightness)
        let sign = lighter ? 1.0 : -1.0
        let minimum = GiftTonalPalette.tableSeparation
        var lab = mixed.oklab
        var color = mixed
        var guardCount = 0
        while (color.oklab.l - backdropLightness) * sign < minimum && guardCount < 40 {
            let target = backdropLightness + sign * (minimum + 0.001 * Double(guardCount))
            lab = lab.with(lightness: min(1.0, max(0.0, target)))
            color = lab.color
            guardCount += 1
        }
        return color
    }

    // On light backdrops mixing toward the tonal panel looks muddy, so darken the backdrop itself just enough for white values.
    internal func lightTable(backdrop: UIColor) -> GiftTableColors? {
        let reference = backdrop.mixedOKLab(with: self.backdropOuterForTable ?? backdrop, alpha: 0.5).oklab
        guard reference.l >= GiftTonalPalette.lightBackdrop else {
            return nil
        }
        let valueNeed = GiftStatsEnvironment.increaseContrast ? 4.5 : GiftTonalPalette.lightValueContrast
        let labelNeed = GiftStatsEnvironment.increaseContrast ? 4.5 : 3.0
        let ink = self.label.withAlphaComponent(1.0)
        var lightness = reference.l - 0.03
        var panel = reference.with(lightness: lightness, chromaScale: 1.12).color
        while lightness > 0.2 && (GiftOKLab.contrast(.white, over: panel) < valueNeed || GiftOKLab.contrast(ink, over: panel) < labelNeed) {
            lightness -= 0.005
            panel = reference.with(lightness: lightness, chromaScale: 1.12).color
        }
        var alpha = self.label.cgColor.alpha
        while alpha < 1.0 && GiftOKLab.contrast(ink.withAlphaComponent(alpha), over: panel) < labelNeed {
            alpha = min(1.0, alpha + 0.02)
        }
        return GiftTableColors(panel: panel, separator: panel.mixedOKLab(with: .white, alpha: 0.16), label: ink.withAlphaComponent(alpha))
    }
}
