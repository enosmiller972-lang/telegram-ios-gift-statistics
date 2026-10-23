import Foundation
import UIKit
import Display
import ComponentFlow

/// Stats views as ends of the card morph (`GiftMorph`). Headings and panels without a counterpart in the card ride the edge
/// of a piece as blocks (`GiftStatsContentComponent.View.morphBlocks`).
public struct GiftStatsMorph {
    public struct Panel {
        public var kind: GiftStatsBackPlan.Panel
        public var end: GiftMorphEnd
        /// The closed log, whose rows morph row by row into the card's table; other panels cross-dissolve.
        public var carriesRows: Bool
        /// Visible part in card coordinates and its share of the area; `.null` on the way in.
        public var visible: CGRect
        public var share: CGFloat
    }

    public var tiles: [GiftMorphEnd] = []
    /// Tiles out of view on the way back: no piece, kept hidden.
    public var hiddenTiles: [GiftMorphEnd] = []
    /// Top to bottom. At most two become card components (table and bottom button), see `GiftStatsBackAssignment`.
    public var panels: [Panel] = []
    /// The off-screen header is born out of this one.
    public var topmost: GiftMorphEnd? {
        return self.panels.first?.end
    }
    public var showAll: GiftMorphEnd?
    public var buy: GiftMorphEnd?
    public var back: GiftMorphEnd?
    public var blockViews: [UIView] = []
    public var fades: [UIView] = []
    /// The card title morphs into this; the gift name on the card matches its first `titleStem` points.
    public var title: UIView?
    public var titleStem: CGFloat = 0.0
    /// nil on the way in.
    public var plan: GiftStatsBackPlan?
    /// nil when the gift is not the user's.
    public var value: GiftStatsMorphValue?

    public var ends: [GiftMorphEnd] {
        return self.tiles + self.panels.map { $0.end } + [self.showAll, self.buy, self.back].compactMap { $0 }
    }

    public var views: [UIView] {
        return (self.ends + self.hiddenTiles).flatMap { $0.reveal } + self.blockViews + self.fades + (self.title.map { [$0] } ?? []) + (self.value?.views ?? [])
    }
}

extension GiftStatsEmbedded {
    /// Pass `visible` (the visible part of the card) on the way back; it decides which panels get a piece (`GiftStatsBackPlan`).
    public func morph(in card: UIView, visible: CGRect? = nil) -> GiftStatsMorph? {
        guard let content = self.content.view as? GiftStatsContentComponent.View, content.superview != nil, !content.tiles.isEmpty, content.tiles[0].superview != nil else {
            return nil
        }
        let plan = visible.flatMap { GiftStatsBackSelection.plan(of: content, card: card, viewport: $0) }
        // Chart labels would show through the morph; restored by `remove` or when the way in finishes.
        self.labelsGate.isHidden = true
        var morph = GiftStatsMorph()
        if let title = content.title.view, title.superview != nil {
            morph.title = title
            morph.titleStem = content.titleStem
        }
        func hide(_ views: [UIView]) -> () -> Void {
            return {
                for view in views {
                    view.alpha = 0.0
                }
            }
        }
        for tile in content.tiles {
            morph.tiles.append(GiftMorphEnd(
                reveal: [tile],
                look: { tile.morphLook(in: card) },
                things: { isFrozen in [tile.morphThing(in: card, isFrozen: isFrozen)] },
                hide: hide([tile])
            ))
        }
        for kind in plan?.inView ?? [.log] {
            if let end = content.morphPanel(kind, in: card, hide: hide) {
                morph.panels.append(GiftStatsMorph.Panel(
                    kind: kind,
                    end: end,
                    carriesRows: kind == .log && !content.salesLogIsExpanded,
                    visible: plan?.visible[kind] ?? .null,
                    share: plan?.shares[kind] ?? 1.0
                ))
            }
        }
        if let plan, !plan.tilesInView {
            self.dropTiles(&morph)
        }
        // The line under the card's table morphs into "Show All".
        if morph.panels.first?.kind == .log, let log = content.salesLog.view as? GiftStatsRecentSalesComponent.View, let button = log.buttonView {
            morph.showAll = GiftMorphEnd(
                reveal: [],
                look: { button.morphLook(in: card) },
                things: { isFrozen in GiftMorphCapture.picture(onFlat: button, in: card, isFrozen: isFrozen).map { [$0] } ?? [] },
                hide: {}
            )
        }
        if let buy = self.chrome.buyView as? GiftStatsStoreButtonComponent.View {
            morph.buy = GiftMorphEnd(
                reveal: [buy],
                look: {
                    // Shadow and rim are added near the end via `accents`.
                    let frame = buy.convert(buy.bounds, to: card)
                    return GiftMorphLook(frame: frame, radius: frame.height / 2.0, flat: GiftFlat(fill: buy.fill ?? .clear, border: nil))
                },
                things: { isFrozen in
                    guard let content = buy.contentView, let picture = buy.contentPicture() else {
                        return []
                    }
                    let frame = content.convert(content.bounds, to: card)
                    return [isFrozen ? GiftMorphThing(picture: picture, frame: frame) : GiftMorphThing(view: picture, home: { [weak content] in
                        return content?.convert(content?.bounds ?? .zero, to: card) ?? frame
                    })]
                },
                hide: hide([buy]),
                accents: { [weak buy] in
                    return buy?.accents() ?? []
                }
            )
        }
        if let fade = self.chrome.fadeView {
            morph.fades = [fade]
        }
        if let back = self.chrome.leadingView as? GiftStatsBackButtonComponent.View {
            morph.back = GiftMorphEnd(
                reveal: [back],
                look: { back.morphLook(in: card) },
                things: { isFrozen in
                    return GiftMorphCapture.picture(onFlat: back, in: card, isFrozen: isFrozen).map { [$0] } ?? []
                },
                hide: hide([back])
            )
        }

        morph.blockViews = content.blockViews
        morph.plan = plan
        morph.value = content.morphValue(in: card, plan: plan)
        return morph
    }
}

extension GiftStatsEmbedded {
    /// Off-screen tiles get no piece; otherwise they would start above the card.
    fileprivate func dropTiles(_ morph: inout GiftStatsMorph) {
        for tile in morph.tiles {
            tile.hide()
        }
        morph.hiddenTiles = morph.tiles
        morph.tiles = []
    }

    public func morphBlocks(plan: GiftStatsBackPlan?, assigned: [GiftStatsBackPlan.Panel: GiftMorphEnd], itemIsPiece: Bool = true) -> [GiftMorphBlock] {
        guard let content = self.content.view as? GiftStatsContentComponent.View else {
            return []
        }
        return content.morphBlocks(plan: plan, assigned: assigned, itemIsPiece: itemIsPiece)
    }

    /// The card minus the "Buy" button and its fade.
    public func viewport(in card: UIView) -> CGRect {
        var rect = card.bounds
        if let fade = self.chrome.fadeView {
            rect.size.height = max(0.0, min(rect.height, fade.convert(fade.bounds, to: card).minY - rect.minY))
        }
        return rect
    }
}

extension GiftTonalPanelView {
    func morphLook(in card: UIView) -> GiftMorphLook {
        return GiftMorphLook(
            frame: self.convert(self.bounds, to: card),
            radius: GiftTonalPalette.cornerRadius,
            flat: GiftFlat(fill: self.backgroundColor ?? .clear, border: nil)
        )
    }
}
