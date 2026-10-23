import Foundation
import UIKit

/// What is visible when going back. The stats are not scrolled back first: each piece morphs from where it is on screen now
/// (`GiftStatsBackAssignment`, `GiftViewStatsFlowPlan`).
public struct GiftStatsBackPlan {
    public enum Panel: Int {
        case log
        case price
        case sales
    }

    /// Top to bottom.
    public var inView: [Panel]
    /// Panels inside the card bounds, visible or not; hidden ones ride the edge of a morphing piece.
    public var inCard: Set<Panel>
    public var tilesInView: Bool
    public var tilesShare: CGFloat
    /// Below this visible share the tiles fade out in place and the owner's buttons grow out of the table instead.
    public static let tilesSourceShare: CGFloat = 0.5
    public var tilesAreSource: Bool {
        return self.tilesShare >= GiftStatsBackPlan.tilesSourceShare
    }
    /// Visible part of each panel, in card coordinates.
    public var visible: [Panel: CGRect]
    public var shares: [Panel: CGFloat]
    /// 1 when the gift is not the user's.
    public var valueShare: CGFloat = 1.0
    public var valueIsSource: Bool {
        return self.valueShare >= GiftMorphTiming.valueSourceShare
    }
}

/// Builds the plan from the current layout. `viewport` is the card minus the "Buy" button and its fade.
struct GiftStatsBackSelection {
    static let visibleShare: CGFloat = 0.25

    static func plan(of content: GiftStatsContentComponent.View, card: UIView, viewport: CGRect) -> GiftStatsBackPlan? {
        func shown(_ frame: CGRect) -> (share: CGFloat, area: CGFloat) {
            let part = frame.intersection(viewport)
            let area = part.isNull ? 0.0 : part.width * part.height
            return (frame.width * frame.height > 0.0 ? area / (frame.width * frame.height) : 0.0, area)
        }
        let panels: [(panel: GiftStatsBackPlan.Panel, view: UIView)] = [(.log, content.salesLogPanel), (.price, content.pricePanel), (.sales, content.salesPanel)]
        var inView: [GiftStatsBackPlan.Panel] = []
        var inCard = Set<GiftStatsBackPlan.Panel>()
        var largest: (panel: GiftStatsBackPlan.Panel, area: CGFloat, distance: CGFloat)?
        var visibleFrames: [GiftStatsBackPlan.Panel: CGRect] = [:]
        var shares: [GiftStatsBackPlan.Panel: CGFloat] = [:]
        for item in panels where item.view.superview != nil {
            let frame = item.view.convert(item.view.bounds, to: card)
            let visible = shown(frame)
            if frame.intersection(card.bounds).height > 0.0 {
                inCard.insert(item.panel)
            }
            let part = frame.intersection(viewport)
            visibleFrames[item.panel] = part.isNull ? frame : part
            shares[item.panel] = visible.share
            if visible.share >= GiftStatsBackSelection.visibleShare {
                inView.append(item.panel)
            }
            let distance = abs(frame.midY - viewport.midY)
            if let current = largest, visible.area < current.area || (visible.area == current.area && distance >= current.distance) {
                continue
            }
            largest = (item.panel, visible.area, distance)
        }
        // The table always needs a source panel, so fall back to the one with the largest visible area.
        if inView.isEmpty, let largest {
            inView = [largest.panel]
        }
        guard !inView.isEmpty else {
            return nil
        }
        var row = CGRect.null
        for tile in content.tiles where tile.superview != nil {
            row = row.union(tile.convert(tile.bounds, to: card))
        }
        let tilesShare = row.isNull ? 0.0 : shown(row).share
        var plan = GiftStatsBackPlan(inView: inView, inCard: inCard, tilesInView: tilesShare >= GiftStatsBackSelection.visibleShare, tilesShare: tilesShare, visible: visibleFrames, shares: shares)
        if content.itemPanel.superview != nil {
            plan.valueShare = shown(content.itemPanel.convert(content.itemPanel.bounds, to: card)).share
        }
        return plan
    }
}
