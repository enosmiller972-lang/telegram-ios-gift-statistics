import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramPresentationData
import MultilineTextComponent

/// Value cell of the gift card's "Value" row. The table row handles the tap, so this view is not interactive.
public final class GiftStatsRowValueComponent: Component {
    private static let spacing: CGFloat = 5.0

    private let theme: PresentationTheme
    private let gramText: String
    private let usdText: String
    private let viewMoreText: String
    private let dimColor: UIColor?

    /// `gramText` has no currency sign (the glyph is drawn). `dimColor` tints `usdText`; nil uses the theme's secondary colour.
    public init(theme: PresentationTheme, gramText: String, usdText: String, viewMoreText: String, dimColor: UIColor? = nil) {
        self.theme = theme
        self.gramText = gramText
        self.usdText = usdText
        self.viewMoreText = viewMoreText
        self.dimColor = dimColor
    }

    public static func ==(lhs: GiftStatsRowValueComponent, rhs: GiftStatsRowValueComponent) -> Bool {
        return lhs.theme === rhs.theme && lhs.gramText == rhs.gramText && lhs.usdText == rhs.usdText && lhs.viewMoreText == rhs.viewMoreText && lhs.dimColor == rhs.dimColor
    }

    public final class View: UIView {
        private let glyph = GiftStatsGram.make()
        private let price = ComponentView<Empty>()
        private let usd = ComponentView<Empty>()
        private let more = ComponentView<Empty>()

        override init(frame: CGRect) {
            super.init(frame: frame)
            self.isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(component: GiftStatsRowValueComponent, availableSize: CGSize, transition: ComponentTransition) -> CGSize {
            let theme = component.theme
            let spacing = GiftStatsRowValueComponent.spacing
            // The table row provides the VoiceOver label.
            self.accessibilityElementsHidden = true

            let glyphSide = GiftStatsGram.side(fontSize: 15.0)
            let glyphGap = GiftStatsGram.gap(fontSize: 15.0)
            self.glyph.color = theme.list.itemPrimaryTextColor
            let moreSize = self.more.update(
                transition: .immediate,
                component: AnyComponent(GiftStatsInfoButtonComponent(text: component.viewMoreText, color: theme.list.itemPrimaryTextColor, action: { _ in })),
                environment: {},
                containerSize: availableSize
            )
            // When narrow, drop the dollars first, then truncate the price; the pill always stays.
            let fixedWidth = glyphSide + glyphGap + spacing + moreSize.width
            let usdSize = self.usd.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(text: .plain(NSAttributedString(string: component.usdText, font: Font.regular(15.0), textColor: component.dimColor ?? theme.list.itemSecondaryTextColor)), maximumNumberOfLines: 1)),
                environment: {},
                containerSize: CGSize(width: max(0.0, availableSize.width - fixedWidth), height: availableSize.height)
            )
            let priceSize = self.price.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(text: .plain(NSAttributedString(string: component.gramText, font: Font.regular(15.0), textColor: theme.list.itemPrimaryTextColor)), maximumNumberOfLines: 1)),
                environment: {},
                containerSize: CGSize(width: max(0.0, availableSize.width - fixedWidth), height: availableSize.height)
            )
            let showsUsd = fixedWidth + priceSize.width + spacing + usdSize.width <= availableSize.width + 0.5
            let height = max(priceSize.height, moreSize.height)
            if self.glyph.superview == nil {
                self.addSubview(self.glyph)
            }
            var x: CGFloat = 0.0
            self.glyph.frame = CGRect(x: 0.0, y: floorToScreenPixels((height - glyphSide) / 2.0), width: glyphSide, height: glyphSide)
            x += glyphSide + glyphGap
            let usdItem: (ComponentView<Empty>, CGSize) = (self.usd, showsUsd ? usdSize : .zero)
            let items: [(ComponentView<Empty>, CGSize)] = [(self.price, priceSize), usdItem, (self.more, moreSize)]
            for (componentView, size) in items {
                if let view = componentView.view {
                    if view.superview == nil {
                        self.addSubview(view)
                    }
                    view.isHidden = componentView === self.usd && !showsUsd
                    view.frame = CGRect(origin: CGPoint(x: x, y: floorToScreenPixels((height - size.height) / 2.0)), size: size)
                }
                if componentView === self.usd && !showsUsd {
                    continue
                }
                x += size.width + spacing
            }
            return CGSize(width: x - spacing, height: height)
        }
    }

    public func makeView() -> View {
        return View(frame: CGRect())
    }

    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, transition: transition)
    }
}
