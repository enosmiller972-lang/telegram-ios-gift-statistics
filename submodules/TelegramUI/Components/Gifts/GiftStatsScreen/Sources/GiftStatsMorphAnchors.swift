import Foundation
import UIKit
import Display
import ComponentFlow

/// Stats panels as morph ends (`GiftStatsBackPlan`, `GiftStatsBackAssignment`). Views with no counterpart in the card ride the edge of a piece.
extension GiftStatsContentComponent.View {
    private func present(_ list: [UIView?]) -> [UIView] {
        return list.compactMap { $0 }.filter { $0.superview != nil }
    }

    /// The closed log yields its rows (matched row by row with the card's table), the open log and charts a single snapshot.
    func morphPanel(_ panel: GiftStatsBackPlan.Panel, in card: UIView, hide: ([UIView]) -> () -> Void) -> GiftMorphEnd? {
        switch panel {
        case .log:
            guard let log = self.salesLog.view as? GiftStatsRecentSalesComponent.View, log.superview != nil, self.salesLogPanel.superview != nil else {
                return nil
            }
            let view = self.salesLogPanel
            let reveal = [view, log]
            let isOpen = self.salesLogIsExpanded
            return GiftMorphEnd(
                reveal: reveal,
                look: { view.morphLook(in: card) },
                things: { isFrozen in
                    if isOpen {
                        return log.morphList().map { [GiftMorphCapture.thing($0, standingFor: log, in: card, isFrozen: isFrozen)] } ?? []
                    }
                    return log.morphRows(in: card, isFrozen: isFrozen)
                },
                hide: hide(reveal)
            )
        case .price:
            return self.chartEnd(panel: self.pricePanel, chart: self.priceChart.view, in: card, hide: hide)
        case .sales:
            return self.chartEnd(panel: self.salesPanel, chart: self.salesChart.view, in: card, hide: hide)
        }
    }

    private func chartEnd(panel: GiftTonalPanelView, chart: UIView?, in card: UIView, hide: ([UIView]) -> () -> Void) -> GiftMorphEnd? {
        guard let chart = chart as? GiftStatsChartComponent.View, chart.superview != nil, panel.superview != nil else {
            return nil
        }
        let reveal = [panel, chart]
        return GiftMorphEnd(
            reveal: reveal,
            look: { panel.morphLook(in: card) },
            things: { isFrozen in
                return chart.morphPicture().map { [GiftMorphCapture.thing($0, standingFor: chart, in: card, isFrozen: isFrozen)] } ?? []
            },
            hide: hide(reveal)
        )
    }

    var blockViews: [UIView] {
        return self.present([self.subtitle.view, self.salesLogHeader.view, self.salesLogPanel, self.salesLog.view, self.priceHeader.view, self.pricePanel, self.priceChart.view, self.salesHeader.view, self.salesPanel, self.salesChart.view])
    }

    /// `plan` is nil on the way in: the log's heading rides its top edge and everything below rides its bottom edge.
    /// On the way back a heading rides its own piece's top edge; a panel without a piece rides the nearest piece above it
    /// (or the first piece's top edge), and panels outside the card stay put unless the log is the table's piece.
    func morphBlocks(plan: GiftStatsBackPlan?, assigned: [GiftStatsBackPlan.Panel: GiftMorphEnd], itemIsPiece: Bool = true) -> [GiftMorphBlock] {
        // The user's gift panel fades in place when it is not a piece.
        var head: [GiftMorphBlock] = []
        if let subtitle = self.subtitle.view, subtitle.superview != nil {
            head.append(GiftMorphBlock(views: [subtitle], ride: .still, window: GiftMorphTiming.valueHeading))
        }
        if !itemIsPiece, self.itemPanel.superview != nil {
            head.append(GiftMorphBlock(views: [self.itemPanel, self.itemRow], ride: .still, window: plan == nil ? GiftMorphTiming.blocks : GiftMorphTiming.headings))
        }
        let sections: [(panel: GiftStatsBackPlan.Panel, header: UIView?, views: [UIView?])] = [
            (.log, self.salesLogHeader.view, [self.salesLogPanel, self.salesLog.view]),
            (.price, self.priceHeader.view, [self.pricePanel, self.priceChart.view]),
            (.sales, self.salesHeader.view, [self.salesPanel, self.salesChart.view])
        ]
        guard let plan else {
            var blocks: [GiftMorphBlock] = []
            for section in sections {
                if section.panel == .log {
                    blocks.append(GiftMorphBlock(views: self.present([section.header]), ride: .top))
                } else {
                    blocks.append(GiftMorphBlock(views: self.present([section.header] + section.views), ride: .bottom))
                }
            }
            return head + blocks.filter { !$0.views.isEmpty }
        }
        let logEnd = assigned[.log]
        let ordered = assigned.keys.sorted { $0.rawValue < $1.rawValue }
        func window(of end: GiftMorphEnd) -> GiftMorphWindow {
            return end === logEnd ? GiftMorphTiming.blocks : GiftMorphTiming.headings
        }
        var blocks: [GiftMorphBlock] = []
        for section in sections {
            let everything = self.present([section.header] + section.views)
            let above = ordered.filter { $0.rawValue < section.panel.rawValue }.last
            if let end = assigned[section.panel] {
                blocks.append(GiftMorphBlock(views: self.present([section.header]), ride: .top, panel: end, window: window(of: end)))
            } else if let above, let end = assigned[above], logEnd != nil {
                blocks.append(GiftMorphBlock(views: everything, ride: .bottom, panel: end, window: window(of: end)))
            } else if !plan.inCard.contains(section.panel) {
                blocks.append(GiftMorphBlock(views: everything, ride: .still, window: GiftMorphTiming.headings))
            } else if let above, let end = assigned[above] {
                blocks.append(GiftMorphBlock(views: everything, ride: .bottom, panel: end, window: window(of: end)))
            } else if let first = ordered.first, let end = assigned[first] {
                blocks.append(GiftMorphBlock(views: everything, ride: .top, panel: end, window: window(of: end)))
            } else {
                blocks.append(GiftMorphBlock(views: everything, ride: .still, window: GiftMorphTiming.headings))
            }
        }
        return head + blocks.filter { !$0.views.isEmpty }
    }
}
