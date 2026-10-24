import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramCore
import TelegramPresentationData
import AccountContext
import GiftStats

/// Gift stats hosted by a card: `contentView` goes into the host's scroll view, the chrome is laid out over the card.
/// The host owns sizing, scrolling and transitions (it animates `revealViews` and `chromeViews`).
public final class GiftStatsEmbedded {
    private let context: AccountContext
    private let gift: StarGift.UniqueGift
    private let controller: () -> ViewController?
    private let openStore: (ViewController) -> Void
    let content = ComponentView<Empty>()
    let chrome = GiftStatsChrome()
    private let state = EmptyComponentState()
    private let collectionStats: GiftStats
    /// nil when the gift is not the user's.
    private let item: GiftStatsYourItem?
    private let sell: () -> Void
    private let openSale: (ViewController, [GiftSale], Int, UIView) -> Void
    private let openItem: (ViewController, UIView) -> Void
    private var isUpdating = false
    let labelsGate = GiftStatsLabelsGate()
    private weak var card: UIView?

    /// Called when the content changes on its own (e.g. a sales page arrived); the host should lay it out again.
    public var updated: ((ComponentTransition) -> Void)?
    public init(
        context: AccountContext,
        gift: StarGift.UniqueGift,
        collectionStats: GiftStats,
        item: GiftStatsYourItem? = nil,
        controller: @escaping () -> ViewController?,
        openStore: @escaping (ViewController) -> Void,
        sell: @escaping () -> Void = {},
        openSale: @escaping (ViewController, [GiftSale], Int, UIView) -> Void = { _, _, _, _ in },
        openItem: @escaping (ViewController, UIView) -> Void = { _, _ in }
    ) {
        self.context = context
        self.gift = gift
        self.collectionStats = collectionStats
        self.item = item
        self.sell = sell
        self.openSale = openSale
        self.openItem = openItem
        self.controller = controller
        self.openStore = openStore
        self.state._updated = { [weak self] transition, _ in
            guard let self, !self.isUpdating else {
                return
            }
            self.updated?(transition)
        }
    }

    /// Hides the chart date labels during the morph, otherwise they show through the "Buy" button surface.
    public var isMorphing: Bool {
        get {
            return self.labelsGate.isHidden
        }
        set {
            self.labelsGate.isHidden = newValue
        }
    }

    public var contentView: UIView? {
        return self.content.view
    }

    /// Top to bottom, in reveal order.
    public var revealViews: [UIView] {
        return (self.content.view as? GiftStatsContentComponent.View)?.revealViews ?? []
    }

    public func setAccessibilityHidden(_ hidden: Bool) {
        self.content.view?.accessibilityElementsHidden = hidden
        for view in self.revealViews + self.chrome.views {
            view.accessibilityElementsHidden = hidden
        }
    }

    public var accessibilityFocus: UIView? {
        return self.chrome.leadingView
    }

    public var chromeViews: [UIView] {
        return self.chrome.views
    }

    /// Prewarms the Core Image context used by the digit blur; call once stats are known to be available.
    public static func prepare() {
        GiftStatsImageContext.prewarm()
    }

    public static func footerReserve(bottomInset: CGFloat) -> CGFloat {
        return GiftStatsChrome.footerReserve(bottomInset: bottomInset)
    }

    /// `parent` is the host's scroll view. Returns the content height.
    public func layoutContent(in parent: UIView, width: CGFloat, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat, transition: ComponentTransition) -> CGFloat {
        self.isUpdating = true
        defer {
            self.isUpdating = false
        }
        GiftStatsNumericTextView.separators = (dateTimeFormat.groupingSeparator, dateTimeFormat.decimalSeparator)
        GiftStatsNumericPiece.warmUp()
        self.content.parentState = self.state
        let size = self.content.update(
            transition: transition,
            component: AnyComponent(GiftStatsContentComponent(
                context: self.context,
                strings: strings,
                dateTimeFormat: dateTimeFormat,
                sideInset: 16.0,
                gift: self.gift,
                collectionStats: self.collectionStats,
                item: self.item,
                sell: { [weak self] in
                    self?.sell()
                },
                openSale: { [weak self] sales, index, source in
                    if let self, let controller = self.controller() {
                        self.openSale(controller, sales, index, source)
                    }
                },
                openItem: { [weak self] source in
                    if let self, let controller = self.controller() {
                        self.openItem(controller, source)
                    }
                },
                buyChanged: { [weak self] listed, floor in
                    self?.chrome.buy = (listed, floor)
                },
                labelsGate: self.labelsGate,
                viewport: { [weak self] in
                    return self?.visibleContentRect()
                }
            )),
            environment: {},
            containerSize: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        if let view = self.content.view {
            if view.superview !== parent {
                parent.addSubview(view)
            }
            view.frame = CGRect(origin: .zero, size: size)
        }
        return size.height
    }

    private func visibleContentRect() -> CGRect? {
        guard let card = self.card, let content = self.content.view else {
            return nil
        }
        return card.convert(self.viewport(in: card), to: content)
    }

    public func scrolled(offset: CGFloat) {
        (self.content.view as? GiftStatsContentComponent.View)?.scrolled(offset: offset)
    }

    /// Scroll needed to fit the just-opened sales log (positive moves content up); nil when none.
    public func takeSalesLogReveal() -> CGFloat? {
        return (self.content.view as? GiftStatsContentComponent.View)?.takeSalesLogReveal()
    }

    /// Shift of the "Show All" button since it was pressed (negative is up); nil when not pressed.
    public func takeSalesLogButtonShift() -> CGFloat? {
        return (self.content.view as? GiftStatsContentComponent.View)?.takeSalesLogButtonShift()
    }

    /// `parent` is the card and `color` its background colour.
    public func layoutChrome(
        in parent: UIView,
        size: CGSize,
        bottomInset: CGFloat,
        color: UIColor,
        leadingIcon: String,
        leading: @escaping () -> Void,
        strings: PresentationStrings,
        dateTimeFormat: PresentationDateTimeFormat,
        transition: ComponentTransition
    ) {
        GiftStatsNumericTextView.separators = (dateTimeFormat.groupingSeparator, dateTimeFormat.decimalSeparator)
        self.card = parent
        self.chrome.update(
            parent: parent,
            size: size,
            bottomInset: bottomInset,
            color: color,
            theme: self.context.sharedContext.currentPresentationData.with { $0 }.theme,
            leadingIcon: leadingIcon,
            leadingTile: GiftStatsTileStyle.surface(palette: GiftTonalPalette.cached(gift: self.gift, style: .craft)),
            leadingAction: leading,
            strings: strings,
            dateTimeFormat: dateTimeFormat,
            money: GiftStatsMoney(context: self.context),
            openStore: { [weak self] in
                if let self, let controller = self.controller() {
                    self.openStore(controller)
                }
            },
            transition: transition
        )
    }

    public func remove() {
        self.labelsGate.isHidden = false
        self.content.view?.removeFromSuperview()
        self.chrome.remove()
        self.card = nil
    }
}
