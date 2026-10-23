import Foundation
import UIKit
import GiftStatsScreen

/// Maps gift card views to statistics components during bidirectional morphing.
/// Reverse transitions adapt based on scroll position (`GiftStatsBackPlan`).
enum GiftViewStatsFlowPlan {
    /// The pairs of the morph, and the panels of the statistics that have a piece (the end of each): what has none rides a piece (`GiftStatsEmbedded.morphBlocks`).
    struct Result {
        var pairs: [GiftMorphPair]
        var carried: [GiftStatsBackPlan.Panel: GiftMorphEnd]
        /// What lies over the pieces (the heading of the panel of the person's own gift).
        var extras: [GiftMorphExtra] = []
        /// The panel of the person's own gift is a piece of this morph (it comes out of the table): the statistics do not fade it by themselves then.
        var itemIsPiece = false
    }

    /// Which panels of the statistics take the table and the bottom button of the card: from where each is on the screen now and where the places are in the card (nil: no panel in view).
    static func assignment(parts: GiftViewStatsParts, stats: GiftStatsMorph) -> GiftStatsBackAssignment? {
        let candidates = stats.panels.map { GiftStatsBackAssignment.Candidate(panel: $0.kind, visible: $0.visible, share: $0.share) }
        return GiftStatsBackAssignment.make(candidates: candidates, table: parts.table?.look.frame, button: parts.footer?.look.frame)
    }

    static func plan(parts: GiftViewStatsParts, stats: GiftStatsMorph, avoiding band: ClosedRange<CGFloat>? = nil) -> Result {
        let assignment = self.assignment(parts: parts, stats: stats)
        let table = assignment.flatMap { chosen in stats.panels.first(where: { $0.kind == chosen.table }) }
        let button = assignment?.button.flatMap { chosen in stats.panels.first(where: { $0.kind == chosen }) }
        var pairs = self.headerPairs(parts: parts, stats: stats, table: table?.end, avoiding: band)
        var carried: [GiftStatsBackPlan.Panel: GiftMorphEnd] = [:]

        // The table footer line stays text: it rides the table's bottom edge and fades; Show All fades in over the panel on its own.
        var showAllOnPanel: GiftMorphPair?
        if let showAll = stats.showAll, table?.kind == .log {
            showAllOnPanel = GiftMorphPair(card: nil, stats: showAll, dissolves: true, window: GiftMorphTiming.showAll)
        }
        if parts.footerText != nil {
            pairs.append(GiftMorphPair(card: parts.footerText, stats: nil, ridesBelow: table?.end, window: GiftMorphTiming.line))
        }
        if let table {
            carried[table.kind] = table.end
            pairs.append(GiftMorphPair(card: parts.table, stats: table.end, isAnchor: true, dissolves: !table.carriesRows, isQuick: band != nil, window: GiftMorphTiming.rows))
        }
        if let showAllOnPanel {
            pairs.append(showAllOnPanel)
        }
        if let button {
            carried[button.kind] = button.end
            pairs.append(GiftMorphPair(card: parts.footer, stats: button.end, dissolves: true, anchorsBottom: true))
        }
        // Corner buttons map to the back button; leftovers fade in place.
        for (index, corner) in parts.corners.enumerated() {
            pairs.append(GiftMorphPair(card: corner, stats: index == 0 ? stats.back : nil, window: GiftMorphTiming.title))
        }
        if parts.corners.isEmpty, let back = stats.back {
            pairs.append(GiftMorphPair(card: nil, stats: back, near: parts.table, window: GiftMorphTiming.title))
        }
        // Footer button maps to Buy; Buy fades out if another panel took footer.
        if let buy = stats.buy, button != nil, let footer = parts.footer {
            pairs.append(GiftMorphPair(card: nil, stats: buy, near: footer, fadesOut: true, anchorsBottom: true, window: GiftMorphTiming.fadeOut))
        } else if parts.footer != nil || stats.buy != nil {
            pairs.append(GiftMorphPair(card: parts.footer, stats: stats.buy, anchorsBottom: true, fillsInWindow: true, window: GiftMorphTiming.buy))
        }
        var result = Result(pairs: pairs, carried: carried)
        self.addValue(to: &result, parts: parts, stats: stats, avoiding: band)
        return result
    }

    /// Morphs the "Your Item" panel from the card's attributes table.
    private static func addValue(to result: inout Result, parts: GiftViewStatsParts, stats: GiftStatsMorph, avoiding band: ClosedRange<CGFloat>?) {
        guard let value = stats.value else {
            return
        }
        if let table = parts.table, band == nil, stats.plan?.valueIsSource ?? true {
            result.pairs.append(GiftMorphPair(card: nil, stats: value.panel, near: table, window: GiftMorphTiming.valueRow))
            result.itemIsPiece = true
        }
        result.extras.append(GiftStatsHeadingReveal(lines: value.lines))
    }

    /// Header buttons ↔ tiles pairing.
    private static func headerPairs(parts: GiftViewStatsParts, stats: GiftStatsMorph, table: GiftMorphEnd?, avoiding band: ClosedRange<CGFloat>?) -> [GiftMorphPair] {
        var pairs: [GiftMorphPair] = []
        if !(stats.plan?.tilesAreSource ?? true) {
            for tile in stats.tiles {
                pairs.append(GiftMorphPair(card: nil, stats: tile, fadesOut: true, window: GiftMorphTiming.fadeOut))
            }
            for button in parts.buttons {
                pairs.append(GiftMorphPair(card: button, stats: nil, near: table, isBorn: true, isQuick: band != nil))
            }
            return pairs
        }
        let count = max(parts.buttons.count, stats.tiles.count)
        for index in 0 ..< count {
            let button = index < parts.buttons.count ? parts.buttons[index] : nil
            let tile = index < stats.tiles.count ? stats.tiles[index] : nil
            let near = button == nil ? (parts.buttons.last ?? parts.table) : stats.tiles.last
            let merges = button == nil && parts.buttons.isEmpty
            if merges, let tile, band != nil {
                pairs.append(GiftMorphPair(card: nil, stats: tile, fadesOut: true, window: GiftMorphTiming.fadeOut))
                continue
            }
            pairs.append(GiftMorphPair(card: button, stats: tile, near: near, mergesInto: merges ? table : nil))
        }
        return pairs
    }
}
