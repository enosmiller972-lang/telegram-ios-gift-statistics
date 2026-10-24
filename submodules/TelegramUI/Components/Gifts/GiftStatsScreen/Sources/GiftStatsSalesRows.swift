import Foundation
import UIKit
import Display
import ComponentFlow

/// Recycles sales rows: the log can be hundreds of rows long, so only the visible rows plus `margin` exist.
final class GiftStatsSalesRows {
    struct Layout {
        let width: CGFloat
        let now: Int32
        let isRTL: Bool
        let count: Int
        let canExpand: Bool
    }

    static let margin = 2
    /// Hysteresis so scrolling back and forth by a row does not recreate it.
    private static let slack = 2
    private static let spareLimit = 6

    private let container: UIView
    private let offset: () -> CGFloat
    private var rows: [Int: GiftStatsSalesRowView] = [:]
    private var spare: [GiftStatsSalesRowView] = []
    private var component: GiftStatsRecentSalesComponent?
    private var layout: Layout?
    /// The number of rows the list had when it was last laid out: a row with a higher number is a row that has just come (a page that has been read, or the rows the list opens with), not
    /// one that the scroll brought near.
    private var knownCount = 0

    /// `container` is the view the rows are put in (the scroll view of the list), `offset` tells how far it is scrolled.
    init(container: UIView, offset: @escaping () -> CGFloat) {
        self.container = container
        self.offset = offset
    }

    /// The row with this number, when it is made.
    func row(at index: Int) -> GiftStatsSalesRowView? {
        return self.rows[index]
    }

    /// How many rows are made now.
    var madeCount: Int {
        return self.rows.count
    }

    /// The numbers of the rows to be made for a window of `height` points of a list of `count` rows, scrolled by `offset`, with `margin` rows more above and below it.
    static func range(offset: CGFloat, height: CGFloat, count: Int, margin: Int) -> Range<Int> {
        guard count > 0 else {
            return 0 ..< 0
        }
        let rowHeight = GiftStatsSalesRowView.height
        let last = max(0, min(count - 1, Int(ceil((offset + height) / rowHeight)) - 1 + margin))
        let first = min(max(0, Int(floor(offset / rowHeight)) - margin), last)
        return first ..< last + 1
    }

    /// The numbers of the rows that are made when the list is laid out as `layout` (all the rows of the closed list; the rows of the window of the open one, from its top when it is just
    /// opening).
    private func window(margin: Int, isOpening: Bool = false) -> Range<Int> {
        guard let component = self.component, let layout = self.layout else {
            return 0 ..< 0
        }
        guard component.isExpanded else {
            return 0 ..< layout.count
        }
        let height = GiftStatsRecentSalesComponent.openRows * GiftStatsSalesRowView.height
        return GiftStatsSalesRows.range(offset: isOpening ? 0.0 : self.offset(), height: height, count: layout.count, margin: margin)
    }

    private func frame(of index: Int, width: CGFloat) -> CGRect {
        return CGRect(x: 0.0, y: CGFloat(index) * GiftStatsSalesRowView.height, width: width, height: GiftStatsSalesRowView.height)
    }

    /// The list is laid out: the rows of its window are made and put where they are, the rows that are far from it are taken away, the rows that the list has no more fade out.
    /// `isOpening`: the open list has just come.
    func update(component: GiftStatsRecentSalesComponent, previous: GiftStatsRecentSalesComponent?, layout: Layout, transition: ComponentTransition, isAnimated: Bool, isOpening: Bool) {
        self.component = component
        self.layout = layout
        let reduceMotion = GiftStatsEnvironment.reduceMotion
        for index in self.window(margin: GiftStatsSalesRows.margin, isOpening: isOpening) {
            let frame = self.frame(of: index, width: layout.width)
            if let row = self.rows[index] {
                self.configure(row, index: index, animated: isAnimated)
                transition.setFrame(view: row, frame: frame)
                continue
            }
            let row = self.make(index: index)
            row.frame = frame
            guard index >= self.knownCount else {
                continue
            }
            if isAnimated && isOpening && index >= GiftStatsRecentSalesComponent.collapsedCount && CGFloat(index) < GiftStatsRecentSalesComponent.openRows {
                // The rows that come with a spring when the list opens are the ones that show; the ones further down are simply there when it is scrolled.
                row.alpha = 0.0
                row.transform = CGAffineTransform(translationX: 0.0, y: -10.0)
                UIView.animate(withDuration: 0.45, delay: Double(index - GiftStatsRecentSalesComponent.collapsedCount) * 0.035, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.4, options: [.allowUserInteraction], animations: {
                    row.alpha = 1.0
                    row.transform = .identity
                })
            } else if previous != nil && index >= GiftStatsRecentSalesComponent.collapsedCount && !isOpening && !reduceMotion {
                // A page that has been read: its rows come in.
                row.alpha = 0.0
                UIView.animate(withDuration: 0.2, delay: 0.0, options: [.allowUserInteraction], animations: {
                    row.alpha = 1.0
                })
            }
        }
        self.knownCount = layout.count
        self.takeAway(except: self.window(margin: GiftStatsSalesRows.margin + GiftStatsSalesRows.slack, isOpening: isOpening))
        // The rows that are not shown any more fade out.
        for (index, row) in self.rows where index >= layout.count {
            self.rows.removeValue(forKey: index)
            if reduceMotion {
                row.removeFromSuperview()
                continue
            }
            UIView.animate(withDuration: 0.2, animations: {
                row.alpha = 0.0
            }, completion: { _ in
                row.removeFromSuperview()
            })
        }
    }

    /// The open list is scrolled: the rows that have come near the window are made, the rows that have gone far from it are taken away.
    func scrolled() {
        guard let layout = self.layout, self.component?.isExpanded == true else {
            return
        }
        for index in self.window(margin: GiftStatsSalesRows.margin) where self.rows[index] == nil {
            self.make(index: index).frame = self.frame(of: index, width: layout.width)
        }
        self.takeAway(except: self.window(margin: GiftStatsSalesRows.margin + GiftStatsSalesRows.slack))
    }

    /// A row for the sale `index`, in its place, from the rows that have been taken away or new.
    private func make(index: Int) -> GiftStatsSalesRowView {
        let row = self.spare.popLast() ?? self.makeNew()
        self.rows[index] = row
        self.container.addSubview(row)
        self.configure(row, index: index, animated: false)
        return row
    }

    private func makeNew() -> GiftStatsSalesRowView {
        return GiftStatsSalesRowView()
    }

    private func takeAway(except kept: Range<Int>) {
        guard let layout = self.layout else {
            return
        }
        for (index, row) in self.rows where index < layout.count && !kept.contains(index) {
            self.rows.removeValue(forKey: index)
            row.removeFromSuperview()
            row.prepareForReuse()
            if self.spare.count < GiftStatsSalesRows.spareLimit {
                self.spare.append(row)
            }
        }
    }

    /// `animated`: the row that shows another sale than before changes its numbers with the numeric transition (a row that has just been given a sale does not).
    private func configure(_ row: GiftStatsSalesRowView, index: Int, animated: Bool) {
        guard let component = self.component, let layout = self.layout, index < component.sales.count else {
            return
        }
        let isLast = index == layout.count - 1 && !layout.canExpand
        row.tapped = component.sales[index].gift == nil || component.openSale == nil ? nil : { [weak self, weak row] in
            if let row {
                self?.component?.openSale?(index, row.iconView)
            }
        }
        row.update(sale: component.sales[index], context: component.context, money: component.money, strings: component.strings, dateTimeFormat: component.dateTimeFormat, palette: component.palette, now: layout.now, width: layout.width, isLast: isLast, isRTL: layout.isRTL, animated: animated)
    }
}
