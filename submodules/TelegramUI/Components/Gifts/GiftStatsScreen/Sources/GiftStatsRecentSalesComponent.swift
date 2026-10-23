import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramCore
import TelegramPresentationData
import AccountContext
import GiftStats

/// The sales log. Closed it shows five rows, the last one under a fog with "Show All" on top (adding no height).
/// Open it becomes a scrolling list that loads more pages near its end, with "Show Less" below.
final class GiftStatsRecentSalesComponent: Component {
    static let collapsedCount = 5
    /// The trailing half row hints that the list scrolls.
    static var openRows: CGFloat {
        return CGFloat(self.collapsedCount) + 2.5
    }
    static let buttonHeight: CGFloat = 38.0
    static var openFooterHeight: CGFloat {
        return 6.0 + self.buttonHeight + 14.0
    }

    /// Fits the open log with its heading and "Show Less" in the viewport: N.5 rows, from 2.5 up to `openRows`.
    static func openHeight(viewport: CGFloat, header: CGFloat, margins: CGFloat) -> CGFloat {
        let rowHeight = GiftStatsSalesRowView.height
        let room = viewport - margins - header - self.openFooterHeight
        let rows = min(self.openRows, max(2.5, floor(room / rowHeight - 0.5) + 0.5))
        return rows * rowHeight
    }
    private static let spinnerHeight: CGFloat = 44.0

    let context: AccountContext
    let money: GiftStatsMoney
    let strings: PresentationStrings
    let dateTimeFormat: PresentationDateTimeFormat
    let palette: GiftTonalPalette
    /// Rounded to the minute.
    let now: Int32
    let sales: [GiftSale]
    let hasMore: Bool
    let isLoadingMore: Bool
    let isExpanded: Bool
    /// nil uses `openRows`.
    let openHeight: CGFloat?
    /// See `GiftStatsSalesListView.cardShortfall`.
    let cardShortfall: (() -> CGFloat)?
    let openSale: ((Int, UIView) -> Void)?
    let toggle: () -> Void
    let loadMore: () -> Void

    init(context: AccountContext, money: GiftStatsMoney, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat, palette: GiftTonalPalette, now: Int32, sales: [GiftSale], hasMore: Bool, isLoadingMore: Bool, isExpanded: Bool, openHeight: CGFloat? = nil, cardShortfall: (() -> CGFloat)? = nil, openSale: ((Int, UIView) -> Void)? = nil, toggle: @escaping () -> Void, loadMore: @escaping () -> Void) {
        self.context = context
        self.money = money
        self.strings = strings
        self.dateTimeFormat = dateTimeFormat
        self.palette = palette
        self.now = now
        self.sales = sales
        self.hasMore = hasMore
        self.isLoadingMore = isLoadingMore
        self.isExpanded = isExpanded
        self.openHeight = openHeight
        self.cardShortfall = cardShortfall
        self.openSale = openSale
        self.toggle = toggle
        self.loadMore = loadMore
    }

    static func ==(lhs: GiftStatsRecentSalesComponent, rhs: GiftStatsRecentSalesComponent) -> Bool {
        return lhs.context === rhs.context && lhs.money == rhs.money && lhs.strings === rhs.strings && lhs.palette == rhs.palette && lhs.now == rhs.now && lhs.sales == rhs.sales && lhs.hasMore == rhs.hasMore && lhs.isLoadingMore == rhs.isLoadingMore && lhs.isExpanded == rhs.isExpanded && lhs.openHeight == rhs.openHeight
    }

    final class View: UIView {
        private let list = GiftStatsSalesListView()
        private let fog = GiftStatsFogView()
        private let spinner = UIActivityIndicatorView(style: .medium)
        private let button = GiftFlatTonalView()
        private let buttonLabel = UILabel()
        private var component: GiftStatsRecentSalesComponent?
        /// Non-nil while the list is closed and fades out at the bottom.
        private var closedFadeHeight: CGFloat?
        private lazy var rowSet = GiftStatsSalesRows(container: self.list.contentView, offset: { [weak self] in
            return self?.list.contentOffset ?? 0.0
        }, contentChanged: { [weak self] in
            self?.fogRevision += 1
            self?.scheduleFogBake()
        })

        private let fogBaker = GiftStatsFogBaker()
        private var fogRevision = 0
        private var isFogBakeScheduled = false

        var buttonCenterY: CGFloat? {
            return self.button.superview == nil ? nil : self.button.center.y
        }

        var buttonView: GiftFlatTonalView? {
            return self.button.superview == nil ? nil : self.button
        }

        /// Snapshot without the button, which morphs separately.
        func morphList() -> UIView? {
            let wasHidden = self.button.isHidden
            self.button.isHidden = true
            defer {
                self.button.isHidden = wasHidden
            }
            return GiftMorphCapture.picture(of: self)
        }

        /// The closed rows, matched row by row with the card's table; each yields a snapshot and a separate price.
        func morphRows(in card: UIView, isFrozen: Bool) -> [GiftMorphThing] {
            var things: [GiftMorphThing] = []
            for index in 0 ..< GiftStatsRecentSalesComponent.collapsedCount {
                // The fogged last row is a single baked image, price included.
                let fogged = self.closedFadeHeight != nil && !GiftStatsEnvironment.reduceTransparency && index == self.rowSet.madeCount - 1 ? self.rowSet.row(at: index).flatMap { self.foggedPicture(of: $0, index: index, isFrozen: isFrozen) } : nil
                guard let row = self.rowSet.row(at: index), let picture = fogged ?? row.morphPicture() else {
                    break
                }
                let frame = row.convert(row.bounds, to: card)
                let path = GiftMorphThing.Path.row(index)
                // Apply the list fade too, so nothing jumps when the real list takes over.
                picture.layer.mask = self.fadeMask(forRow: index)
                if isFrozen {
                    things.append(GiftMorphThing(picture: picture, frame: frame, path: path))
                } else {
                    things.append(GiftMorphThing(view: picture, path: path, home: { [weak row, weak card] in
                        guard let row, let card else {
                            return frame
                        }
                        return row.convert(row.bounds, to: card)
                    }))
                }
                if fogged != nil {
                    continue
                }
                let price = row.morphPriceThing(path: path, in: card, isFrozen: isFrozen)
                price.view.layer.mask = self.fadeMask(forRow: index)
                things.append(price)
            }
            return things
        }

        /// Cached bake if current; on the way in an image view filled when the background bake ends; when frozen, baked now.
        private func foggedPicture(of row: GiftStatsSalesRowView, index: Int, isFrozen: Bool) -> UIImageView? {
            guard let component = self.component else {
                return GiftStatsFogBake.picture(of: row)
            }
            let source = GiftStatsFogBaker.Source(component: component, revision: self.fogRevision, size: row.bounds.size)
            if isFrozen {
                return self.fogBaker.imageNow(for: source, flat: { GiftStatsFogBake.flatImage(of: row) }).map { GiftStatsFogBake.view(of: $0, size: source.size) }
            }
            if let image = self.fogBaker.image(for: source) {
                return GiftStatsFogBake.view(of: image, size: source.size)
            }
            guard let flat = GiftStatsFogBake.flatImage(of: row) else {
                return nil
            }
            self.fogBaker.start(source, flat: flat)
            return self.fogBaker.picture(for: source, flat: flat, within: self.fogDeadline(forRow: index))
        }

        /// Slightly before the row's swap window in the morph, when it first becomes visible.
        private func fogDeadline(forRow index: Int) -> Double {
            let start = Double(GiftMorphTiming.rows.start + CGFloat(index) * GiftMorphTiming.rowStep)
            return start * GiftMorphTiming.duration * max(1.0, UIView.animationDurationFactor) * 0.8
        }

        /// Deferred one run loop turn so the row is laid out; the blur runs in the background.
        private func scheduleFogBake() {
            guard self.closedFadeHeight != nil, !GiftStatsEnvironment.reduceTransparency, !self.isFogBakeScheduled else {
                return
            }
            self.isFogBakeScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.isFogBakeScheduled = false
                guard let component = self.component, self.closedFadeHeight != nil, !GiftStatsEnvironment.reduceTransparency, let row = self.rowSet.row(at: self.rowSet.madeCount - 1) else {
                    return
                }
                let source = GiftStatsFogBaker.Source(component: component, revision: self.fogRevision, size: row.bounds.size)
                guard !self.fogBaker.isMade(source), let flat = GiftStatsFogBake.flatImage(of: row) else {
                    return
                }
                self.fogBaker.start(source, flat: flat)
            }
        }

        private func fadeMask(forRow index: Int) -> CALayer? {
            guard let height = self.closedFadeHeight else {
                return nil
            }
            let rowHeight = GiftStatsSalesRowView.height
            let mask = CAGradientLayer()
            mask.frame = CGRect(x: 0.0, y: 0.0, width: self.bounds.width, height: rowHeight)
            mask.startPoint = CGPoint(x: 0.5, y: 0.0)
            mask.endPoint = CGPoint(x: 0.5, y: 1.0)
            let steps = 8
            mask.colors = (0 ... steps).map { step in
                UIColor(white: 0.0, alpha: GiftStatsSalesListView.closedFadeAlpha(y: CGFloat(index) * rowHeight + rowHeight * CGFloat(step) / CGFloat(steps) + 0.01, height: height)).cgColor
            }
            mask.locations = (0 ... steps).map { NSNumber(value: Double($0) / Double(steps)) }
            return mask
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            self.addSubview(self.list)
            self.addSubview(self.fog)
            self.spinner.color = GiftStatsLook.secondaryTextColor
            self.spinner.hidesWhenStopped = true
            self.list.contentView.addSubview(self.spinner)
            self.list.scrolled = { [weak self] in
                self?.rowSet.scrolled()
            }
            self.list.nearEnd = { [weak self] in
                if let component = self?.component, component.isExpanded, component.hasMore, !component.isLoadingMore {
                    component.loadMore()
                }
            }
            self.buttonLabel.font = Font.semibold(14.0)
            self.buttonLabel.textColor = GiftStatsLook.textColor
            self.buttonLabel.textAlignment = .center
            self.buttonLabel.isUserInteractionEnabled = false
            self.button.addSubview(self.buttonLabel)
            self.button.action = { [weak self] in
                self?.component?.toggle()
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(component: GiftStatsRecentSalesComponent, availableSize: CGSize, transition: ComponentTransition) -> CGSize {
            let previous = self.component
            self.component = component
            self.list.cardShortfall = component.cardShortfall
            let width = availableSize.width
            let now = component.now
            let isRTL = GiftStatsEnvironment.isRTL(strings: component.strings)
            let reduceMotion = GiftStatsEnvironment.reduceMotion
            let rowHeight = GiftStatsSalesRowView.height
            let canExpand = component.sales.count > GiftStatsRecentSalesComponent.collapsedCount || component.hasMore
            let count = component.isExpanded ? component.sales.count : min(component.sales.count, GiftStatsRecentSalesComponent.collapsedCount)
            let spinnerHeight = component.isExpanded && component.isLoadingMore ? GiftStatsRecentSalesComponent.spinnerHeight : 0.0
            let contentHeight = CGFloat(count) * rowHeight + spinnerHeight
            let listHeight = component.isExpanded ? min(component.openHeight ?? GiftStatsRecentSalesComponent.openRows * rowHeight, contentHeight) : CGFloat(count) * rowHeight
            let isOpening = component.isExpanded && previous?.isExpanded != true
            let isAnimated: Bool
            if case .none = transition.animation {
                isAnimated = false
            } else {
                isAnimated = !reduceMotion
            }

            let layout = GiftStatsSalesRows.Layout(width: width, now: now, isRTL: isRTL, count: count, canExpand: canExpand)
            self.rowSet.update(component: component, previous: previous, layout: layout, transition: transition, isAnimated: isAnimated, isOpening: isOpening)

            let closedFade = canExpand && !component.isExpanded
            self.closedFadeHeight = closedFade ? listHeight : nil
            self.list.update(height: listHeight, width: width, contentHeight: contentHeight, isOpen: component.isExpanded, closedFade: closedFade, transition: transition)
            transition.setFrame(view: self.list, frame: CGRect(origin: .zero, size: CGSize(width: width, height: listHeight)))
            let fogSize = CGSize(width: width, height: min(listHeight, rowHeight))
            if closedFade {
                self.fog.update(size: fogSize)
                let fogFrame = CGRect(origin: CGPoint(x: 0.0, y: listHeight - fogSize.height), size: fogSize)
                if self.fog.isShownNow {
                    transition.setFrame(view: self.fog, frame: fogFrame)
                } else {
                    self.fog.frame = fogFrame
                }
            }
            // With Reduce Transparency the list's mask alone fades the last row.
            self.fog.setShown(closedFade && !GiftStatsEnvironment.reduceTransparency, duration: isAnimated ? 0.4 : 0.0)
            if spinnerHeight > 0.0 {
                self.spinner.frame = CGRect(x: floor((width - 20.0) / 2.0), y: CGFloat(count) * rowHeight + 12.0, width: 20.0, height: 20.0)
                self.spinner.startAnimating()
            } else {
                self.spinner.stopAnimating()
            }

            var height = listHeight
            if canExpand {
                let title = component.isExpanded ? component.strings.Gift_Stats_ShowLess : component.strings.Gift_Stats_ShowAll
                self.buttonLabel.text = title
                self.button.label = title
                let labelSize = self.buttonLabel.sizeThatFits(CGSize(width: 200.0, height: 24.0))
                let size = CGSize(width: ceil(labelSize.width) + 40.0, height: GiftStatsRecentSalesComponent.buttonHeight)
                if self.button.superview == nil {
                    self.addSubview(self.button)
                }
                self.button.update(flat: component.palette.button, radius: size.height / 2.0)
                self.buttonLabel.frame = CGRect(origin: CGPoint(x: 20.0, y: floor((size.height - ceil(labelSize.height)) / 2.0)), size: CGSize(width: ceil(labelSize.width), height: ceil(labelSize.height)))
                let buttonY = component.isExpanded ? height + 6.0 : height - rowHeight / 2.0 - size.height / 2.0
                let frame = CGRect(x: floor((width - size.width) / 2.0), y: buttonY, width: size.width, height: size.height)
                if self.button.bounds.size == .zero {
                    self.button.bounds = CGRect(origin: .zero, size: size)
                    self.button.center = frame.center
                } else {
                    transition.setPosition(view: self.button, position: frame.center)
                    transition.setBounds(view: self.button, bounds: CGRect(origin: .zero, size: size))
                    self.button.updateRim(size: size, transition: transition)
                }
                if component.isExpanded {
                    height += 6.0 + size.height + 14.0
                }
            } else {
                self.button.removeFromSuperview()
            }
            self.scheduleFogBake()
            return CGSize(width: width, height: height)
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, transition: transition)
    }
}
