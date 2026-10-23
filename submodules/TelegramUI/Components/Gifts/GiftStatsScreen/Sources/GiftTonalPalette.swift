import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramCore
import GiftStats
import GiftCraftBackdrop

// Panel and control colours for the gift sheet, derived from the backdrop by GiftTonalDerivation.
// The craft style uses the Craft Gift tint for everything.
public struct GiftTonalPalette: Equatable {
    public static let cornerRadius: CGFloat = 24.0
    public static let inset: CGFloat = 16.0
    public static let rim = UIColor(white: 1.0, alpha: 0.30)

    public let tint: UIColor
    public let panel: UIColor
    public let separator: UIColor
    public let label: UIColor
    public let dim: UIColor
    public let value: UIColor = .white
    // On the sheet: tile, selector track, back button.
    public let surface: GiftFlat
    // On a panel or track: selector thumb, "Show All".
    public let button: GiftFlat
    // nil for the craft style.
    private let backdropInner: UIColor?
    private let backdropOuter: UIColor?
    let backdropBehindTable: UIColor?
    let backdropOuterForTable: UIColor?

    private init(source: UIColor, isFlat: Bool, native: GiftTonalDerivation.Native? = nil, backdrop: (inner: UIColor, outer: UIColor)? = nil) {
        let derivation = GiftTonalDerivation.make(source: source, isFlat: isFlat, native: native)
        let panel = derivation.panel
        self.backdropInner = backdrop?.inner
        self.backdropOuter = backdrop?.outer
        self.backdropBehindTable = backdrop == nil ? nil : source
        self.backdropOuterForTable = backdrop?.outer
        var tint = derivation.control
        var button = derivation.button
        if let backdrop {
            // Controls follow the backdrop behind them (GiftControlTone), not the panel.
            let tone = GiftControlTone.cachedTone(inner: backdrop.inner, outer: backdrop.outer, outerShare: 1.0)
            tint = tone.color
            button = GiftTonalPalette.button(over: tone)
        }
        self.tint = tint
        self.panel = panel
        self.surface = GiftFlat(fill: tint, border: GiftTonalPalette.rim)
        self.button = GiftFlat(fill: button, border: GiftTonalPalette.rim)
        self.separator = panel.mixedOKLab(with: .white, alpha: 0.12)
        self.label = GiftStatsContrast.legible(derivation.label, over: [panel, tint])
        self.dim = GiftStatsContrast.legible(derivation.dim, over: [panel, tint])
    }

    // Share of the inner (radial) colour left at the top of the table.
    private static let tableInnerShare: CGFloat = 0.10

    public init(inner: UIColor, outer: UIColor) {
        self.init(inner: inner, outer: outer, pattern: nil, text: nil)
    }

    init(inner: UIColor, outer: UIColor, pattern: UIColor?, text: UIColor?) {
        let behindTable = outer.mixedOKLab(with: inner, alpha: GiftTonalPalette.tableInnerShare)
        var native: GiftTonalDerivation.Native?
        if let pattern, let text {
            native = GiftTonalDerivation.Native(pattern: pattern, text: text)
        }
        self.init(source: behindTable, isFlat: false, native: native, backdrop: (inner, outer))
    }

    private static func button(over tone: GiftControlTone.Tone) -> UIColor {
        let step = GiftTonalDerivation.buttonStep * (tone.step < 0.0 ? -1.0 : 1.0)
        let lab = tone.color.oklab
        return lab.with(lightness: min(1.0, max(0.0, lab.l + step))).color
    }

    // outerShare: 0 = brightest inner light behind the control, 1 = outer colour only.
    public func surface(outerShare: CGFloat) -> GiftFlat {
        guard let inner = self.backdropInner, let outer = self.backdropOuter, outerShare < 1.0 else {
            return self.surface
        }
        return GiftFlat(fill: GiftControlTone.cachedTone(inner: inner, outer: outer, outerShare: outerShare).color, border: GiftTonalPalette.rim)
    }

    public enum Style {
        case backdrop
        case craft
    }

    private final class Cached {
        let palette: GiftTonalPalette

        init(_ palette: GiftTonalPalette) {
            self.palette = palette
        }
    }
    private static let cache = NSCache<NSString, Cached>()

    public static func cached(gift: StarGift.UniqueGift, style: Style = .backdrop) -> GiftTonalPalette {
        var key = (style == .craft ? "craft" : "backdrop") + "|\(GiftStatsEnvironment.increaseContrast)"
        if style == .backdrop {
            for attribute in gift.attributes {
                if case let .backdrop(_, _, innerColor, outerColor, patternColor, textColor, _) = attribute {
                    key += "|\(innerColor)|\(outerColor)|\(patternColor)|\(textColor)"
                }
            }
        }
        if let cached = self.cache.object(forKey: key as NSString) {
            return cached.palette
        }
        let palette = GiftTonalPalette(gift: gift, style: style)
        self.cache.setObject(Cached(palette), forKey: key as NSString)
        return palette
    }

    public init(gift: StarGift.UniqueGift, style: Style = .backdrop) {
        if style == .craft {
            self.init(source: GiftCraftBackdropColors.standard.tint, isFlat: true)
            return
        }
        var inner = UIColor(rgb: 0x5aa7e6)
        var outer = UIColor(rgb: 0x2f6fbd)
        var pattern: UIColor?
        var text: UIColor?
        for attribute in gift.attributes {
            if case let .backdrop(_, _, innerColor, outerColor, patternColor, textColor, _) = attribute {
                inner = UIColor(rgb: UInt32(bitPattern: innerColor))
                outer = UIColor(rgb: UInt32(bitPattern: outerColor))
                // Placeholder backdrops have both colours set to 0.
                if patternColor != 0 || textColor != 0 {
                    pattern = UIColor(rgb: UInt32(bitPattern: patternColor))
                    text = UIColor(rgb: UInt32(bitPattern: textColor))
                }
            }
        }
        self.init(inner: inner, outer: outer, pattern: pattern, text: text)
    }
}

public final class GiftTonalPanelView: UIView {
    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.layer.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(color: UIColor, radius: CGFloat = GiftTonalPalette.cornerRadius) {
        self.backgroundColor = color
        self.layer.cornerRadius = radius
    }
}

public final class GiftTonalPanelComponent: Component {
    public let color: UIColor

    public init(color: UIColor) {
        self.color = color
    }

    public static func ==(lhs: GiftTonalPanelComponent, rhs: GiftTonalPanelComponent) -> Bool {
        return lhs.color == rhs.color
    }

    public func makeView() -> GiftTonalPanelView {
        return GiftTonalPanelView(frame: CGRect())
    }

    public func update(view: GiftTonalPanelView, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        view.update(color: self.color)
        return availableSize
    }
}
