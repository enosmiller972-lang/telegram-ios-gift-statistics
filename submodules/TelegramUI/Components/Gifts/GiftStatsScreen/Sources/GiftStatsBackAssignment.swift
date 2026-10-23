import Foundation
import CoreGraphics

/// On the way back, the visible panel nearest to the card's table morphs into it, and the nearest one below it into
/// the bottom button if mostly visible (otherwise "Buy" does). See `GiftViewStatsFlowPlan`.
public struct GiftStatsBackAssignment: Equatable {
    public struct Candidate {
        public var panel: GiftStatsBackPlan.Panel
        /// Visible part of the panel, in card coordinates.
        public var visible: CGRect
        /// Visible fraction of the panel's area, 0...1.
        public var share: CGFloat

        public init(panel: GiftStatsBackPlan.Panel, visible: CGRect, share: CGFloat) {
            self.panel = panel
            self.visible = visible
            self.share = share
        }

        var area: CGFloat {
            return self.visible.isNull ? 0.0 : self.visible.width * self.visible.height
        }
    }

    public static let buttonShare: CGFloat = 0.5
    /// Distances closer than this (pt) are a tie; the panel with the larger visible area wins.
    static let tie: CGFloat = 0.5

    public var table: GiftStatsBackPlan.Panel
    public var button: GiftStatsBackPlan.Panel?

    /// `table` and `button` are their final frames in the card. Returns nil when no panel is visible.
    public static func make(candidates: [Candidate], table: CGRect?, button: CGRect?) -> GiftStatsBackAssignment? {
        let panels = candidates.sorted { $0.panel.rawValue < $1.panel.rawValue }
        guard !panels.isEmpty else {
            return nil
        }
        let source: Candidate
        if let table, panels.count > 1 {
            source = GiftStatsBackAssignment.nearest(panels, to: table.midY)
        } else {
            source = GiftStatsBackAssignment.largest(panels)
        }
        var below: Candidate?
        if let button {
            let lower = panels.filter { $0.panel.rawValue > source.panel.rawValue && $0.share >= GiftStatsBackAssignment.buttonShare }
            if !lower.isEmpty {
                below = GiftStatsBackAssignment.nearest(lower, to: button.midY)
            }
        }
        return GiftStatsBackAssignment(table: source.panel, button: below?.panel)
    }

    private static func nearest(_ list: [Candidate], to y: CGFloat) -> Candidate {
        func distance(_ item: Candidate) -> CGFloat {
            return item.visible.isNull ? CGFloat.greatestFiniteMagnitude : abs(item.visible.midY - y)
        }
        var best = list[0]
        for item in list.dropFirst() {
            let a = distance(item)
            let b = distance(best)
            if a < b - GiftStatsBackAssignment.tie || (abs(a - b) <= GiftStatsBackAssignment.tie && item.area > best.area) {
                best = item
            }
        }
        return best
    }

    private static func largest(_ list: [Candidate]) -> Candidate {
        var best = list[0]
        for item in list.dropFirst() where item.area > best.area {
            best = item
        }
        return best
    }
}
