import Foundation
import UIKit
import GiftStatsScreen

/// Return from stats scrolled past their header: the card's gift is born small out of the topmost visible panel and grows into
/// place, with the title and lines following. If the header is at least half visible, `GiftViewStatsFlow` glides it instead.
struct GiftViewStatsBorn {
    struct Pose {
        /// 0 at birth, 1 in place.
        var travel: CGFloat
        var title: CGFloat
        var scale: CGFloat
        /// Offset from the gift's place in the card.
        var shift: CGPoint
    }

    /// The born gift never starts above the back button row.
    private static let backRowBottom: CGFloat = 64.0

    private let start: CGPoint
    private let place: CGPoint
    /// Offsets below the gift center in the card.
    private let titleOffset: CGFloat
    let lines: [(view: UIView, offset: CGFloat)]
    /// Vertical span of the header in card coordinates.
    let band: ClosedRange<CGFloat>

    /// At least half of both the gift and the collection title are inside the card.
    static func isHeaderInView(gift: UIView?, title: UIView?, card: UIView) -> Bool {
        func share(_ view: UIView?) -> CGFloat {
            guard let view, view.bounds.height > 0.0 else {
                return 0.0
            }
            let frame = view.convert(view.bounds, to: card)
            let shown = frame.intersection(card.bounds)
            return shown.isNull ? 0.0 : shown.height / frame.height
        }
        return share(gift) >= 0.5 && share(title) >= 0.5
    }

    /// Nil when the gift's place is scrolled out of the card or no panel is visible.
    init?(parts: GiftViewStatsParts, stats: GiftStatsMorph, card: UIView) {
        guard let gift = parts.gift, let superview = gift.superview, let panel = stats.topmost else {
            return nil
        }
        let place = superview.convert(gift.center, to: card)
        guard card.bounds.contains(place) else {
            return nil
        }
        // Start at the visible top of the panel, below the back button row, with the whole small gift below that line.
        let frame = panel.look.frame
        let shown = frame.intersection(card.bounds)
        let area = shown.isNull ? frame : shown
        self.start = CGPoint(x: area.midX, y: max(area.minY, GiftViewStatsBorn.backRowBottom) + gift.bounds.height * GiftMorphTiming.bornScale / 2.0)
        self.place = place
        self.titleOffset = parts.title.map { $0.convert($0.bounds, to: card).midY - place.y } ?? 0.0
        var lines: [(view: UIView, offset: CGFloat)] = []
        for view in parts.others {
            if let parent = view.superview {
                lines.append((view: view, offset: parent.convert(view.center, to: card).y - place.y))
            }
        }
        self.lines = lines
        var bottom = place.y + gift.bounds.height / 2.0
        if let title = parts.title {
            bottom = max(bottom, title.convert(title.bounds, to: card).maxY)
        }
        for view in parts.others {
            bottom = max(bottom, view.convert(view.bounds, to: card).maxY)
        }
        self.band = (place.y - gift.bounds.height / 2.0) ... bottom
    }

    func pose(at time: CGFloat) -> Pose {
        let travel = GiftMorphTiming.back(GiftMorphTiming.bornGift, at: time)
        let scale = GiftMorphTiming.bornScale + (1.0 - GiftMorphTiming.bornScale) * travel
        let shift = CGPoint(x: (self.start.x - self.place.x) * (1.0 - travel), y: (self.start.y - self.place.y) * (1.0 - travel))
        return Pose(travel: travel, title: GiftMorphTiming.back(GiftMorphTiming.bornTitle, at: time), scale: scale, shift: shift)
    }

    /// Keeps a view `offset` below the gift at a scaled distance, plus `GiftMorphTiming.bornGap` while in flight.
    func shift(below offset: CGFloat, pose: Pose) -> CGPoint {
        return CGPoint(x: pose.shift.x, y: pose.shift.y + offset * (pose.scale - 1.0) + GiftMorphTiming.bornGap * (1.0 - pose.travel))
    }

    func titleShift(pose: Pose) -> CGPoint {
        return self.shift(below: self.titleOffset, pose: pose)
    }
}
