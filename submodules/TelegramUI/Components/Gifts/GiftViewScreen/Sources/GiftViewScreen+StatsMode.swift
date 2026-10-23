import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramCore
import TelegramPresentationData
import AccountContext
import GiftStats
import GiftStatsScreen
import GiftCraftBackdrop

/// Parameters for opening collection statistics from a gift card.
struct GiftViewStatsRequest {
    let context: AccountContext
    let gift: StarGift.UniqueGift
    let collectionStats: GiftStats
    let item: GiftStatsYourItem?
    let valueRow: UIView?
    let openStore: (ViewController) -> Void
    let sell: () -> Void
    let openSale: (ViewController, [GiftSale], Int, UIView) -> Void
    let openItem: (ViewController, UIView) -> Void
}

/// Host views modified during statistics presentation.
struct GiftViewStatsHost {
    let card: UIView
    let scrollView: UIScrollView
    let content: UIView
    let controlPanel: UIView?
    let footer: GiftViewStatsFooter
}

/// Controls the fluid transition between the gift card and collection statistics.
final class GiftViewStatsMode {
    enum Phase {
        case entering
        case active
        case leaving
        case gone
    }

    private static let crossfadeDuration: Double = 0.25
    private static var cardTransition: ComponentTransition {
        return ComponentTransition(animation: .curve(duration: GiftMorphTiming.duration, curve: .custom(GiftMorphTiming.controlPoints.0, GiftMorphTiming.controlPoints.1, GiftMorphTiming.controlPoints.2, GiftMorphTiming.controlPoints.3)))
    }

    private let palette: GiftTonalPalette
    private(set) var phase: Phase = .entering
    let embedded: GiftStatsEmbedded
    private let requestUpdate: (ComponentTransition) -> Void
    private let finished: () -> Void
    private weak var card: UIView?
    private weak var scrollView: UIScrollView?
    private var parts: GiftViewStatsParts?
    private var morph: GiftMorph?
    private var flow: GiftViewStatsFlow?
    private var cardOffset: CGFloat = 0.0
    private var restoresOffset = false
    private var startHeight: CGFloat = 0.0
    private var knownViews = Set<ObjectIdentifier>()

    /// The card is turning into the statistics or back (the morph runs, or is about to).
    var isTransitioning: Bool {
        return self.phase == .entering || self.phase == .leaving
    }

    /// False once the card has gone back: the card is laid out as the card, over the statistics that are still flowing away.
    var showsStats: Bool {
        return self.phase == .entering || self.phase == .active
    }

    init(request: GiftViewStatsRequest, controller: @escaping () -> ViewController?, requestUpdate: @escaping (ComponentTransition) -> Void, finished: @escaping () -> Void) {
        self.palette = GiftTonalPalette.cached(gift: request.gift)
        self.requestUpdate = requestUpdate
        self.finished = finished
        self.embedded = GiftStatsEmbedded(context: request.context, gift: request.gift, collectionStats: request.collectionStats, item: request.item, controller: controller, openStore: request.openStore, sell: request.sell, openSale: request.openSale, openItem: request.openItem)
        self.embedded.updated = { [weak self] transition in
            self?.requestUpdate(transition)
        }
    }

    // MARK: Background

    // MARK: Background

    /// Card background color while statistics are presented.
    func cardColor(_ base: UIColor?) -> UIColor? {
        guard base != nil, self.showsStats else {
            return base
        }
        return GiftCraftBackdropColors.standard.bottom
    }

    /// Overscroll background color while statistics are presented.
    func overscrollColor() -> UIColor? {
        guard self.showsStats else {
            return nil
        }
        return GiftCraftBackdropColors.standard.top
    }

    // MARK: Layout

    /// Lays out statistics content in the host scroll view.
    func layoutContent(in scrollView: UIScrollView, width: CGFloat, bottomInset: CGFloat, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat, transition: ComponentTransition) -> CGFloat {
        let height = self.embedded.layoutContent(in: scrollView, width: width, strings: strings, dateTimeFormat: dateTimeFormat, transition: transition)
        self.hideNewViews(self.embedded.revealViews)
        return height + GiftStatsEmbedded.footerReserve(bottomInset: bottomInset)
    }

    func layoutChrome(in card: UIView, size: CGSize, bottomInset: CGFloat, color: UIColor, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat, transition: ComponentTransition) {
        self.embedded.layoutChrome(in: card, size: size, bottomInset: bottomInset, color: color, leadingIcon: "Navigation/Back", leading: { [weak self] in
            self?.leave()
        }, strings: strings, dateTimeFormat: dateTimeFormat, transition: transition)
        self.hideNewViews(self.embedded.chromeViews)
    }

    /// Hides newly created statistics views until the transition reveals them.
    private func hideNewViews(_ views: [UIView]) {
        for view in views where self.knownViews.insert(ObjectIdentifier(view)).inserted && self.phase == .entering {
            view.alpha = 0.0
            view.accessibilityElementsHidden = true
        }
    }

    /// Re-applies hidden state to card elements that transitioned away.
    func reapplyHidden() {
        self.parts?.reapply()
    }

    func scrolled(offset: CGFloat) {
        if self.phase == .active {
            self.embedded.scrolled(offset: offset)
        }
    }

    // MARK: Enter

    func enter(host: GiftViewStatsHost, valueRow: UIView?) {
        let parts = GiftViewStatsParts(card: host.card, content: host.content, controlPanel: host.controlPanel, footer: host.footer, valueRow: valueRow, palette: self.palette)
        self.parts = parts
        parts.freeze()
        self.card = host.card
        self.scrollView = host.scrollView
        self.cardOffset = host.scrollView.contentOffset.y
        host.card.isUserInteractionEnabled = false
        self.embedded.isMorphing = true
        self.startHeight = host.card.bounds.height

        if UIAccessibility.isReduceMotionEnabled {
            self.placeGift(parts.giftTransform())
        }
        self.requestUpdate(UIAccessibility.isReduceMotionEnabled ? .immediate : GiftViewStatsMode.cardTransition)
        self.startEnter(attempt: 0)
    }

    private func startEnter(attempt: Int) {
        guard self.phase == .entering, let card = self.card, let parts = self.parts else {
            return
        }
        guard let stats = self.embedded.morph(in: card) else {
            if attempt < 80 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.startEnter(attempt: attempt + 1)
                }
            } else {
                self.enterFinished()
            }
            return
        }
        if UIAccessibility.isReduceMotionEnabled {
            self.scrollView?.contentOffset = .zero
            self.crossfade(leaving: parts.allViews, entering: stats.views, craft: 1.0, completion: { [weak self] in
                self?.parts?.hideAll()
                self?.enterFinished()
            })
            return
        }
        if let scrollView = self.scrollView, scrollView.contentOffset.y != 0.0 {
            scrollView.contentOffset = .zero
        }
        let morph = GiftMorph(host: card)
        self.morph = morph
        let flow = GiftViewStatsFlow(parts: parts, stats: stats, card: card, toStats: true, startHeight: self.startHeight)
        self.flow = flow
        let plan = GiftViewStatsFlowPlan.plan(parts: parts, stats: stats)
        morph.run(pairs: plan.pairs, blocks: self.embedded.morphBlocks(plan: nil, assigned: plan.carried, itemIsPiece: plan.itemIsPiece), extras: plan.extras, toStats: true, startHeight: self.startHeight, driver: { moment in
            flow.apply(moment)
        }, completion: { [weak self] in
            flow.finish(toStats: true)
            self?.morph = nil
            self?.flow = nil
            self?.enterFinished()
        })
    }

    private func enterFinished() {
        guard self.phase == .entering, let card = self.card else {
            return
        }
        self.phase = .active
        self.embedded.isMorphing = false
        card.isUserInteractionEnabled = true
        self.parts?.setAccessibilityHidden(true)
        self.embedded.setAccessibilityHidden(false)
        UIAccessibility.post(notification: .screenChanged, argument: self.embedded.accessibilityFocus)
        self.embedded.scrolled(offset: self.scrollView?.contentOffset.y ?? 0.0)
    }

    private func placeGift(_ transform: CGAffineTransform) {
        guard let gift = self.parts?.gift else {
            return
        }
        gift.transform = transform
        self.parts?.moveSymbols(for: transform)
    }

    // MARK: Leave

    /// Reverses the morph transition from statistics back to the card.
    func leave() {
        guard self.phase == .active, let card = self.card, let parts = self.parts else {
            return
        }
        self.phase = .leaving
        self.restoresOffset = true
        card.isUserInteractionEnabled = false
        parts.setAccessibilityHidden(false)
        self.embedded.setAccessibilityHidden(true)
        let isReduced = UIAccessibility.isReduceMotionEnabled
        let stats = self.embedded.morph(in: card, visible: isReduced ? nil : self.embedded.viewport(in: card))
        guard let stats, !isReduced else {
            self.placeGift(.identity)
            self.requestUpdate(.immediate)
            parts.releaseAll()
            self.crossfade(leaving: stats?.views ?? [], entering: parts.allViews, craft: 0.0, completion: { [weak self] in
                self?.leaveFinished()
            })
            return
        }
        for end in stats.ends {
            end.capture(isFrozen: true)
        }
        let isHeaderBorn = !GiftViewStatsBorn.isHeaderInView(gift: parts.gift, title: stats.title, card: card)
        let carried = self.holdStatistics(parts: parts)
        self.startHeight = card.bounds.height
        self.requestUpdate(GiftViewStatsMode.cardTransition)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.phase == .leaving else {
                return
            }
            let morph = GiftMorph(host: card)
            self.morph = morph
            let flow = GiftViewStatsFlow(parts: parts, stats: stats, card: card, toStats: false, startHeight: self.startHeight, carried: carried, isHeaderBorn: isHeaderBorn)
            self.flow = flow
            let plan = GiftViewStatsFlowPlan.plan(parts: parts, stats: stats, avoiding: flow.bornBand)
            morph.run(pairs: plan.pairs, blocks: self.embedded.morphBlocks(plan: stats.plan, assigned: plan.carried, itemIsPiece: plan.itemIsPiece), extras: plan.extras, toStats: false, startHeight: self.startHeight, driver: { moment in
                flow.apply(moment)
            }, completion: { [weak self] in
                flow.finish(toStats: false)
                self?.morph = nil
                self?.flow = nil
                self?.leaveFinished()
            })
        }
    }

    /// Preserves relative scroll positioning during the return transition.
    private func holdStatistics(parts: GiftViewStatsParts) -> CGFloat {
        guard let scrollView = self.scrollView else {
            return 0.0
        }
        let carried = self.cardOffset - scrollView.contentOffset.y
        guard abs(carried) > 0.01 else {
            return 0.0
        }
        scrollView.contentOffset = CGPoint(x: 0.0, y: self.cardOffset)
        self.embedded.contentView?.transform = CGAffineTransform(translationX: 0.0, y: carried)
        parts.setCraftShift(carried)
        return carried
    }

    /// Target scroll offset when restoring card state.
    func takeRestoredOffset() -> CGFloat? {
        guard self.phase == .leaving, self.restoresOffset else {
            return nil
        }
        self.restoresOffset = false
        return self.cardOffset
    }

    /// Cleans up morph state and restores original card hierarchy.
    func teardown() {
        guard self.phase != .gone else {
            return
        }
        self.phase = .gone
        self.morph?.cancel()
        self.morph = nil
        self.flow?.finish(toStats: false)
        self.flow = nil
        self.parts?.restoreCard()
        self.embedded.remove()
        self.embedded.isMorphing = false
        self.card?.isUserInteractionEnabled = true
    }

    private func leaveFinished() {
        guard self.phase != .gone else {
            return
        }
        self.embedded.remove()
        self.parts?.releaseAll()
        self.card?.isUserInteractionEnabled = true
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        self.finished()
    }

    // MARK: Reduce Motion

    /// Crossfades between card and statistics views when motion is reduced.
    private func crossfade(leaving: [UIView], entering: [UIView], craft: CGFloat, completion: @escaping () -> Void) {
        let parts = self.parts
        UIView.animate(withDuration: GiftViewStatsMode.crossfadeDuration, delay: 0.0, options: [.curveEaseInOut], animations: {
            parts?.setCraftLevel(craft)
            for view in leaving {
                view.alpha = 0.0
            }
            for view in entering {
                view.alpha = 1.0
            }
        }, completion: { _ in
            completion()
        })
    }
}
