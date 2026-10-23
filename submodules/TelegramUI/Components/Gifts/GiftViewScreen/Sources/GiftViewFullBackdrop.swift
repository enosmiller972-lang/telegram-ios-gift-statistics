import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramCore
import TelegramPresentationData
import AccountContext
import GiftCardStyle
import GiftStatsScreen
import GiftCraftBackdrop

/// A collectible's backdrop fills the whole sheet. This component draws all of it (light and symbols included) and the header
/// draws only the model, so there is a single fill with no seam.
enum GiftViewFullBackdrop {
    static let theme: PresentationTheme = makeDefaultDarkPresentationTheme(preview: false)

    static func colors(of gift: StarGift.UniqueGift) -> (inner: UIColor, outer: UIColor, pattern: UIColor)? {
        for attribute in gift.attributes {
            if case let .backdrop(_, _, innerColor, outerColor, patternColor, _, _) = attribute {
                return (UIColor(rgb: UInt32(bitPattern: innerColor)), UIColor(rgb: UInt32(bitPattern: outerColor)), UIColor(rgb: UInt32(bitPattern: patternColor)))
            }
        }
        return nil
    }

    static func gift(subject: GiftViewScreen.Subject) -> StarGift.UniqueGift? {
        guard let arguments = subject.arguments, case let .unique(gift) = arguments.gift, GiftViewFullBackdrop.colors(of: gift) != nil else {
            return nil
        }
        return gift
    }
}

final class GiftViewFullBackdropComponent: Component {
    /// Symbols are centered on the model.
    static let modelCenterY: CGFloat = GiftStatsHeaderMetrics.modelRestY
    private static let lightCenterY: CGFloat = 104.0
    /// Matches `giftViewTopOverscrollBackgroundHeight`. Drawn in the same layers so overscroll shows one smooth fill.
    static let overscrollReach: CGFloat = 250.0

    /// The header fades into the outer color over its last `headerFadeHeight` points (55% at 0.6 of the way).
    private static let lightRadiusX: CGFloat = 190.0
    private static let headerFadeHeight: CGFloat = 170.0

    /// Visible share of the outer color at `point`: 0 is the brightest inner color, 1 is pure outer (used by `GiftControlTone`).
    static func outerShare(at point: CGPoint, width: CGFloat, headerHeight: CGFloat) -> CGFloat {
        let reachY = max(150.0, headerHeight - 16.0 - GiftViewFullBackdropComponent.lightCenterY)
        let dx = (point.x - width / 2.0) / GiftViewFullBackdropComponent.lightRadiusX
        let dy = (point.y - GiftViewFullBackdropComponent.lightCenterY) / (reachY + 30.0)
        let light = min(1.0, (dx * dx + dy * dy).squareRoot())
        let f = min(1.0, max(0.0, (point.y - (headerHeight - GiftViewFullBackdropComponent.headerFadeHeight)) / GiftViewFullBackdropComponent.headerFadeHeight))
        let fade = f <= 0.6 ? 0.55 * f / 0.6 : 0.55 + 0.45 * (f - 0.6) / 0.4
        return fade + (1.0 - fade) * light
    }

    /// Corner buttons are centered 38pt from the side and top. Header height barely affects the result there, so the minimum is used.
    static func cornerOuterShare(width: CGFloat) -> CGFloat {
        return self.outerShare(at: CGPoint(x: 38.0, y: 38.0), width: width, headerHeight: 240.0)
    }

    let context: AccountContext
    let gift: StarGift.UniqueGift
    /// The top of the table.
    let symbolsBottom: CGFloat

    init(context: AccountContext, gift: StarGift.UniqueGift, symbolsBottom: CGFloat) {
        self.context = context
        self.gift = gift
        self.symbolsBottom = symbolsBottom
    }

    static func ==(lhs: GiftViewFullBackdropComponent, rhs: GiftViewFullBackdropComponent) -> Bool {
        return lhs.context === rhs.context && lhs.gift == rhs.gift && lhs.symbolsBottom == rhs.symbolsBottom
    }

    final class View: UIView {
        private let light = CAGradientLayer()
        private let field = GiftSymbolFieldView()
        /// The view itself doesn't clip: the light and the Craft background extend above the card for overscroll.
        private let fieldClip = UIView()
        /// Created lazily by `setCraftLevel`; spans from `overscrollReach` above the card to the bottom.
        private var craft: GiftCraftBackdropView?
        private var craftLevel: CGFloat = 0.0
        private var context: AccountContext?
        private var baseHeight: CGFloat = 0.0
        private var extent: CGFloat = 0.0

        override init(frame: CGRect) {
            super.init(frame: frame)
            self.isUserInteractionEnabled = false
            self.fieldClip.clipsToBounds = true
            self.fieldClip.isUserInteractionEnabled = false
            self.light.type = .radial
            self.light.startPoint = CGPoint(x: 0.5, y: 0.5)
            self.light.endPoint = CGPoint(x: 1.0, y: 1.0)
            self.layer.addSublayer(self.light)
            self.addSubview(self.fieldClip)
            self.fieldClip.addSubview(self.field)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// Extends the backdrop to at least `height` for the taller stats content; nil resets to the sheet size. Only grows while
        /// set, since shrinking content animates and must stay painted. Called by the sheet on every layout.
        func setExtent(_ height: CGFloat?) {
            self.extent = height.map { max(self.extent, $0) } ?? 0.0
            let target = max(self.baseHeight, self.extent)
            guard abs(self.bounds.height - target) > 0.5 else {
                return
            }
            self.frame = CGRect(x: self.frame.minX, y: self.frame.minY, width: self.bounds.width, height: target)
            if self.craft != nil {
                self.layoutCraft(size: self.bounds.size)
            }
        }

        func playOpeningWave() {
            self.field.startWave(from: CGPoint(x: self.field.bounds.midX, y: GiftViewFullBackdropComponent.modelCenterY), haptic: false)
        }

        func setSymbolsShift(_ dy: CGFloat) {
            self.field.transform = CGAffineTransform(translationX: 0.0, y: dy)
        }

        /// Crossfades to the Craft Gift background (0...1).
        func setCraftLevel(_ level: CGFloat, symbolsFlow: Bool = false) {
            self.craftLevel = level
            if level > 0.0 && self.craft == nil, self.context != nil {
                let craft = GiftCraftBackdropView()
                // Below the symbols so they can flow into the gift over it.
                self.insertSubview(craft, belowSubview: self.fieldClip)
                self.craft = craft
                self.layoutCraft(size: self.bounds.size)
            }
            self.craft?.alpha = level
            self.craft?.isHidden = level <= 0.0
            // During the morph the symbols leave via `setSymbolsFlow` instead of fading.
            self.field.alpha = symbolsFlow ? 1.0 : 1.0 - level
        }

        /// Keeps the Craft background in place on screen while the card jumps back from scrolled stats.
        func setCraftShift(_ dy: CGFloat) {
            self.craft?.transform = dy == 0.0 ? .identity : CGAffineTransform(translationX: 0.0, y: dy)
        }

        /// 1 means the symbols have flowed into the gift; nil when no flow is running.
        func setSymbolsFlow(_ progress: CGFloat?) {
            self.field.setFlow(progress)
        }

        private func layoutCraft(size: CGSize) {
            guard let craft = self.craft, let context = self.context else {
                return
            }
            // Not `frame`: the view may have a transform.
            craft.bounds = CGRect(origin: .zero, size: size)
            craft.center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
            // Centered on the gift's position in the stats header.
            craft.update(context: context, colors: .standard, size: size, focusY: GiftStatsHeaderMetrics.modelCenterY, topCornerRadius: 0.0, showsPattern: false, topExtension: GiftViewFullBackdropComponent.overscrollReach, transition: .immediate)
        }

        func update(component: GiftViewFullBackdropComponent, availableSize: CGSize) -> CGSize {
            guard let colors = GiftViewFullBackdrop.colors(of: component.gift) else {
                return availableSize
            }
            self.context = component.context
            self.baseHeight = availableSize.height
            var patternFile: TelegramMediaFile?
            for attribute in component.gift.attributes {
                if case let .pattern(_, file, _) = attribute {
                    patternFile = file
                }
            }
            let center = CGPoint(x: availableSize.width / 2.0, y: GiftViewFullBackdropComponent.modelCenterY)
            let lightCenter = CGPoint(x: availableSize.width / 2.0, y: GiftViewFullBackdropComponent.lightCenterY)
            let lightReachY = max(150.0, component.symbolsBottom - lightCenter.y)
            let reachY = max(150.0, component.symbolsBottom - center.y)
            self.backgroundColor = colors.outer
            self.fieldClip.frame = CGRect(origin: .zero, size: availableSize)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let lightSize = CGSize(width: 380.0, height: lightReachY * 2.0 + 60.0)
            self.light.bounds = CGRect(origin: .zero, size: lightSize)
            self.light.position = lightCenter
            self.light.colors = [colors.inner.cgColor, colors.outer.cgColor]
            self.light.locations = [0.0, 1.0]
            CATransaction.commit()
            // Not `frame`: the view may have a transform.
            self.field.bounds = CGRect(origin: .zero, size: availableSize)
            self.field.center = CGPoint(x: availableSize.width / 2.0, y: availableSize.height / 2.0)
            self.field.update(context: component.context, file: patternFile, color: colors.pattern, center: center, size: availableSize, fade: CGSize(width: 280.0, height: reachY))
            if self.craft != nil {
                self.layoutCraft(size: CGSize(width: availableSize.width, height: max(availableSize.height, self.extent)))
            }
            return availableSize
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize)
    }
}

/// Fades the bottom of a collectible header into the backdrop's outer color so there is no edge.
final class GiftViewHeaderFadeComponent: Component {
    let color: UIColor

    init(color: UIColor) {
        self.color = color
    }

    static func ==(lhs: GiftViewHeaderFadeComponent, rhs: GiftViewHeaderFadeComponent) -> Bool {
        return lhs.color == rhs.color
    }

    final class View: UIView {
        private let gradient = CAGradientLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            self.isUserInteractionEnabled = false
            self.gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
            self.gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
            self.layer.addSublayer(self.gradient)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(component: GiftViewHeaderFadeComponent, availableSize: CGSize) -> CGSize {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.gradient.frame = CGRect(origin: .zero, size: availableSize)
            self.gradient.colors = [component.color.withAlphaComponent(0.0).cgColor, component.color.withAlphaComponent(0.55).cgColor, component.color.cgColor]
            self.gradient.locations = [0.0, 0.6, 1.0]
            CATransaction.commit()
            return availableSize
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize)
    }
}
