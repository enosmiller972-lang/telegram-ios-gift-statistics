import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramPresentationData
import TelegramStringFormatting
import EdgeEffect
import GiftStats

/// Fixed overlay above the scrolling stats: the back/close button and, when gifts are listed, the "Buy" button over an edge fade.
final class GiftStatsChrome {
    private static let fadeReach: CGFloat = 48.0
    private static let contentGap: CGFloat = 16.0

    private let leadingButton = ComponentView<Empty>()
    private let buyButton = ComponentView<Empty>()
    private let fade = EdgeEffectView()
    /// Floor in US cents.
    var buy: (listed: Int32, floor: Int64?)?

    var views: [UIView] {
        var views: [UIView] = []
        if let view = self.leadingButton.view, view.superview != nil {
            views.append(view)
        }
        if self.fade.superview != nil && !self.fade.isHidden {
            views.append(self.fade)
        }
        if let view = self.buyButton.view, view.superview != nil, !view.isHidden {
            views.append(view)
        }
        return views
    }

    var leadingView: UIView? {
        if let view = self.leadingButton.view, view.superview != nil {
            return view
        }
        return nil
    }

    var buyView: UIView? {
        if let view = self.buyButton.view, view.superview != nil, !view.isHidden {
            return view
        }
        return nil
    }

    var fadeView: UIView? {
        return self.fade.superview != nil && !self.fade.isHidden ? self.fade : nil
    }

    /// Bottom content inset so the "Buy" button covers nothing at the end of the scroll.
    static func footerReserve(bottomInset: CGFloat) -> CGFloat {
        return GiftStatsStoreButtonComponent.height + GiftStatsStoreButtonComponent.bottomInset(device: bottomInset) + GiftStatsChrome.contentGap
    }

    func update(
        parent: UIView,
        size: CGSize,
        bottomInset: CGFloat,
        color: UIColor,
        theme: PresentationTheme,
        leadingIcon: String,
        leadingTile: GiftStatsTileSurface,
        leadingAction: @escaping () -> Void,
        strings: PresentationStrings,
        dateTimeFormat: PresentationDateTimeFormat,
        money: GiftStatsMoney,
        openStore: @escaping () -> Void,
        transition: ComponentTransition
    ) {
        self.updateBuy(parent: parent, size: size, bottomInset: bottomInset, color: color, theme: theme, strings: strings, dateTimeFormat: dateTimeFormat, money: money, openStore: openStore)

        let buttonSize = self.leadingButton.update(
            transition: .immediate,
            component: AnyComponent(GiftStatsBackButtonComponent(icon: leadingIcon, tile: leadingTile, label: leadingIcon == "Navigation/Back" ? strings.Common_Back : strings.Common_Close, action: leadingAction)),
            environment: {},
            containerSize: CGSize(width: size.width - 32.0, height: GiftStatsBackButtonComponent.side)
        )
        if let view = self.leadingButton.view {
            if view.superview !== parent {
                parent.addSubview(view)
            }
            view.frame = CGRect(origin: CGPoint(x: 16.0, y: 16.0), size: buttonSize)
        }
    }

    func remove() {
        self.leadingButton.view?.removeFromSuperview()
        self.buyButton.view?.removeFromSuperview()
        self.fade.removeFromSuperview()
    }

    /// Splits a one-argument format around the argument so the number can animate on its own.
    private static func line(_ formatted: PresentationStrings.FormattedString, value: String, spoken: String?, isRTL: Bool) -> GiftStatsNumberLineView.Content {
        let text = formatted.string as NSString
        guard let range = formatted.ranges.first?.range, range.location != NSNotFound, NSMaxRange(range) <= text.length else {
            return GiftStatsNumberLineView.Content(prefix: formatted.string, value: "", suffix: "", spoken: spoken, isRTL: isRTL)
        }
        return GiftStatsNumberLineView.Content(prefix: text.substring(to: range.location), value: value, suffix: text.substring(from: NSMaxRange(range)), spoken: spoken, isRTL: isRTL)
    }

    private func updateBuy(parent: UIView, size: CGSize, bottomInset: CGFloat, color: UIColor, theme: PresentationTheme, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat, money: GiftStatsMoney, openStore: @escaping () -> Void) {
        guard let buy = self.buy, buy.listed > 0 else {
            self.buyButton.view?.isHidden = true
            self.fade.isHidden = true
            return
        }
        let isRTL = GiftStatsEnvironment.isRTL(strings: strings)
        let title: GiftStatsNumberLineView.Content
        if let floor = buy.floor {
            let price = money.gram(cents: floor, dateTimeFormat: dateTimeFormat)
            let spokenTitle = strings.Gift_Stats_BuyFrom(money.spokenGram(cents: floor, dateTimeFormat: dateTimeFormat, strings: strings)).string
            var content = GiftStatsChrome.line(strings.Gift_Stats_BuyFrom(price), value: price, spoken: spokenTitle, isRTL: isRTL)
            content.hasGlyph = true
            title = content
        } else {
            title = GiftStatsNumberLineView.Content(prefix: strings.Gift_Stats_Buy, value: "", suffix: "", isRTL: isRTL)
        }
        let label = title.spoken ?? title.text
        let buttonBottom = GiftStatsStoreButtonComponent.bottomInset(device: bottomInset)
        let buttonSize = self.buyButton.update(
            transition: .immediate,
            component: AnyComponent(GiftStatsStoreButtonComponent(title: title, label: label, fill: theme.list.itemCheckColors.fillColor, foreground: theme.list.itemCheckColors.foregroundColor, action: {
                openStore()
            })),
            environment: {},
            containerSize: CGSize(width: size.width - GiftStatsStoreButtonComponent.sideInset * 2.0, height: GiftStatsStoreButtonComponent.height)
        )
        let fadeHeight = buttonSize.height + buttonBottom + GiftStatsChrome.fadeReach
        if self.fade.superview !== parent {
            self.fade.isUserInteractionEnabled = false
            parent.addSubview(self.fade)
        }
        self.fade.isHidden = false
        let fadeFrame = CGRect(x: 0.0, y: size.height - fadeHeight, width: size.width, height: fadeHeight)
        self.fade.frame = fadeFrame
        self.fade.update(content: color.alpha > 0.01 ? color : UIColor(white: 0.1, alpha: 1.0), blur: !GiftStatsEnvironment.reduceTransparency, alpha: 1.0, rect: fadeFrame, edge: .bottom, edgeSize: fadeHeight, transition: .immediate)
        if let view = self.buyButton.view {
            if view.superview !== parent {
                parent.addSubview(view)
            }
            view.isHidden = false
            view.frame = CGRect(x: GiftStatsStoreButtonComponent.sideInset, y: size.height - buttonBottom - buttonSize.height, width: buttonSize.width, height: buttonSize.height)
        }
        if let leading = self.leadingButton.view, leading.superview === parent {
            parent.bringSubviewToFront(leading)
        }
    }
}
