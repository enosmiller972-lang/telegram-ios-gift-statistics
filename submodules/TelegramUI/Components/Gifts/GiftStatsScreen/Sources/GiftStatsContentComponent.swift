import Foundation
import UIKit
import Display
import ComponentFlow
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import GraphCore
import GraphUI
import GiftStats

/// The scrolling collection stats: title, tiles, the user's own gift, the sales log and the two charts.
final class GiftStatsContentComponent: Component {
    let context: AccountContext
    let strings: PresentationStrings
    let dateTimeFormat: PresentationDateTimeFormat
    let sideInset: CGFloat
    let gift: StarGift.UniqueGift
    let collectionStats: GiftStats?
    /// nil when the gift is not the user's.
    let item: GiftStatsYourItem?
    let sell: () -> Void
    /// Sales loaded so far, the tapped index and the view the card grows out of.
    let openSale: ([GiftSale], Int, UIView) -> Void
    let openItem: (UIView) -> Void
    /// Listed count and floor in US cents, for the "Buy" button.
    let buyChanged: (Int32, Int64?) -> Void
    let labelsGate: GiftStatsLabelsGate
    /// Visible part in content coordinates, excluding the "Buy" button and its fade.
    let viewport: () -> CGRect?
    var palette: GiftTonalPalette {
        return GiftTonalPalette.cached(gift: self.gift, style: .craft)
    }

    init(
        context: AccountContext,
        strings: PresentationStrings,
        dateTimeFormat: PresentationDateTimeFormat,
        sideInset: CGFloat,
        gift: StarGift.UniqueGift,
        collectionStats: GiftStats?,
        item: GiftStatsYourItem?,
        sell: @escaping () -> Void,
        openSale: @escaping ([GiftSale], Int, UIView) -> Void,
        openItem: @escaping (UIView) -> Void,
        buyChanged: @escaping (Int32, Int64?) -> Void,
        labelsGate: GiftStatsLabelsGate,
        viewport: @escaping () -> CGRect?
    ) {
        self.context = context
        self.strings = strings
        self.dateTimeFormat = dateTimeFormat
        self.sideInset = sideInset
        self.gift = gift
        self.collectionStats = collectionStats
        self.item = item
        self.sell = sell
        self.openSale = openSale
        self.openItem = openItem
        self.buyChanged = buyChanged
        self.labelsGate = labelsGate
        self.viewport = viewport
    }

    static func ==(lhs: GiftStatsContentComponent, rhs: GiftStatsContentComponent) -> Bool {
        return lhs.context === rhs.context && lhs.strings === rhs.strings && lhs.sideInset == rhs.sideInset && lhs.gift == rhs.gift && lhs.collectionStats == rhs.collectionStats && lhs.item == rhs.item
    }

    final class View: UIView {
        private(set) var component: GiftStatsContentComponent?
        weak var state: EmptyComponentState?

        let tiles = (0 ..< 3).map { _ in GiftStatsValueTileView() }
        let priceHeader = ComponentView<Empty>()
        let pricePanel = GiftTonalPanelView()
        let priceChart = ComponentView<Empty>()
        let salesHeader = ComponentView<Empty>()
        let salesPanel = GiftTonalPanelView()
        let salesChart = ComponentView<Empty>()
        let salesLogHeader = ComponentView<Empty>()
        let salesLogPanel = GiftTonalPanelView()
        let salesLog = ComponentView<Empty>()
        let title = ComponentView<Empty>()
        /// Width of the leading part of the plural title that matches the gift name on the card.
        var titleStem: CGFloat = 0.0
        let subtitle = ComponentView<Empty>()
        let itemHeader = ComponentView<Empty>()
        let itemPanel = GiftTonalPanelView()
        let itemRow = GiftStatsItemRowView()

        var fraction: ClosedRange<CGFloat>?
        var priceToken = 0
        var salesToken = 0
        var scrollOffset: CGFloat = 0.0
        var salesLogIsExpanded = false
        /// The first page comes with the stats; the rest is loaded on scroll.
        struct SalesPages {
            var items: [GiftSale]
            var isLoading: Bool
            var isEnd: Bool
            /// Consecutive failures and backoff; the list end asks for more on every scroll frame.
            var failures = 0
            var retryAfter: Double = 0.0
        }
        /// Doubles per consecutive failure; after `maximumFailures` loading stops until the log is reopened.
        private static let retryDelay = 2.0
        private static let maximumFailures = 3
        var salesPages: SalesPages?
        private let salesDisposables = DisposableSet()
        private var salesLogButtonAnchor: CGFloat?
        /// Fixed when the log is opened, so the whole open log fits in the visible part of the card.
        private(set) var salesLogOpenHeight: CGFloat?
        private var salesLogReveals = false
        /// The top margin keeps the open log clear of the back button.
        private static let revealTopMargin: CGFloat = 72.0
        private static let revealBottomMargin: CGFloat = 12.0
        var cache: (source: GiftStats, localized: GiftStats, series: GiftStatsPriceSeries?)?
        /// nil when not loaded or fewer than two points.
        var salesSeries: GiftStatsPriceSeries?
        private var isUpdating = false

        override init(frame: CGRect) {
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            self.salesDisposables.dispose()
        }

        /// Touches on the empty header pass through to the card's gift and backdrop symbols beneath.
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let hit = super.hitTest(point, with: event)
            if hit === self, point.y < GiftStatsHeaderMetrics.titleCenterY - 22.0 {
                return nil
            }
            return hit
        }

        func update(component: GiftStatsContentComponent, availableSize: CGSize, state: EmptyComponentState, transition: ComponentTransition) -> CGSize {
            self.isUpdating = true
            defer {
                self.isUpdating = false
            }
            self.component = component
            self.state = state
            guard let current = self.currentStats(component: component) else {
                return CGSize(width: availableSize.width, height: 0.0)
            }
            if self.fraction == nil, let series = current.series ?? self.salesSeries {
                self.fraction = GiftStatsInitialRange.fraction(series: series)
            }
            let size = self.layoutContent(component: component, current: current, availableSize: availableSize, transition: transition)
            // The host adds the views to its scroll view only after this returns.
            DispatchQueue.main.async { [weak self] in
                self?.playVisibleIntros()
            }
            return size
        }

        func currentStats(component: GiftStatsContentComponent) -> (stats: GiftStats, series: GiftStatsPriceSeries?)? {
            guard let source = component.collectionStats else {
                return nil
            }
            if let cached = self.cache, cached.source == source {
                return (cached.localized, cached.series)
            }
            self.salesSeries = GiftStatsPriceSeries(graph: source.salesGraph)
            let names = ["y0": component.strings.Gift_Stats_Floor]
            let localized = GiftStats(
                priceGraph: GiftStatsGraphNames.localized(source.priceGraph, names: names, colors: ["y0": "#FFFFFF"]),
                salesGraph: GiftStatsGraphNames.localized(source.salesGraph, names: ["y0": component.strings.Gift_Stats_SalesSeries], colors: ["y0": "#FFFFFF8C"]),
                summary: source.summary,
                recentSales: source.recentSales
            )
            let series = GiftStatsPriceSeries(graph: source.priceGraph)
            self.cache = (source, localized, series)
            return (localized, series)
        }

        func salesPages(for stats: GiftStats) -> SalesPages {
            if let pages = self.salesPages {
                return pages
            }
            let pages = SalesPages(items: stats.recentSales, isLoading: false, isEnd: stats.recentSales.count < Int(GiftStats.salesPageSize))
            self.salesPages = pages
            return pages
        }

        func loadMoreSales() {
            guard let component = self.component, var pages = self.salesPages, !pages.isLoading, !pages.isEnd,
                  pages.failures < View.maximumFailures, CACurrentMediaTime() >= pages.retryAfter else {
                return
            }
            let offset = Int32(pages.items.count)
            pages.isLoading = true
            self.salesPages = pages
            self.salesDisposables.add((GiftStatsService.shared.provider.recentSales(for: component.gift, scope: .collection, offset: offset, limit: GiftStats.salesPageSize)
            |> deliverOnMainQueue).startStrict(next: { [weak self] page in
                guard let self, var pages = self.salesPages else {
                    return
                }
                pages.isLoading = false
                if let page {
                    pages.failures = 0
                    // Drop a page that no longer continues the log; the list will ask again.
                    if pages.items.count == Int(offset) {
                        pages.items.append(contentsOf: page.sales)
                        pages.isEnd = page.sales.isEmpty || Int32(pages.items.count) >= page.count
                    }
                } else {
                    pages.failures += 1
                    pages.retryAfter = CACurrentMediaTime() + View.retryDelay * Double(1 << (pages.failures - 1))
                }
                self.salesPages = pages
                self.state?.updated(transition: .immediate)
            }))
            // Show the spinner now, deferred when called from inside a layout pass.
            if self.isUpdating {
                DispatchQueue.main.async { [weak self] in
                    self?.state?.updated(transition: .immediate)
                }
            } else {
                self.state?.updated(transition: .immediate)
            }
        }

        func toggleSalesLog() {
            // On collapse the host scrolls by the button's shift so it stays under the finger.
            self.salesLogButtonAnchor = self.salesLogButtonCenterY()
            self.salesLogIsExpanded = !self.salesLogIsExpanded
            if self.salesLogIsExpanded {
                self.salesLogButtonAnchor = nil
                self.salesLogReveals = true
                if let viewport = self.component?.viewport(), let header = self.salesLogHeader.view {
                    self.salesLogOpenHeight = GiftStatsRecentSalesComponent.openHeight(viewport: viewport.height, header: header.bounds.height + GiftStatsSpacing.headerToPanel, margins: View.revealTopMargin + View.revealBottomMargin)
                }
            }
            self.salesPages?.failures = 0
            self.salesPages?.retryAfter = 0.0
            self.state?.updated(transition: GiftStatsEnvironment.reduceMotion ? .immediate : .spring(duration: 0.5))
        }

        private func salesLogButtonCenterY() -> CGFloat? {
            guard let log = self.salesLog.view as? GiftStatsRecentSalesComponent.View, let buttonY = log.buttonCenterY else {
                return nil
            }
            return log.frame.minY + buttonY
        }

        /// How far the bottom of the log is below the visible area; 0 or less when it is visible.
        func salesLogShortfall() -> CGFloat {
            guard let viewport = self.component?.viewport(), let log = self.salesLog.view, log.superview != nil else {
                return 0.0
            }
            return log.frame.maxY + View.revealBottomMargin - viewport.maxY
        }

        /// Minimal scroll (positive moves content up) to fit the just-opened log; returned once after opening, else nil.
        func takeSalesLogReveal() -> CGFloat? {
            guard self.salesLogReveals else {
                return nil
            }
            self.salesLogReveals = false
            guard let viewport = self.component?.viewport(), let log = self.salesLog.view, let header = self.salesLogHeader.view else {
                return nil
            }
            let top = header.frame.minY - View.revealTopMargin
            let bottom = log.frame.maxY + View.revealBottomMargin
            let least = bottom - viewport.maxY
            let most = top - viewport.minY
            if least <= 0.0 && most >= 0.0 {
                return nil
            }
            return least > 0.0 ? min(least, max(most, 0.0)) : most
        }

        /// Shift of the sales log button since it was pressed (negative is up).
        func takeSalesLogButtonShift() -> CGFloat? {
            guard let anchor = self.salesLogButtonAnchor else {
                return nil
            }
            self.salesLogButtonAnchor = nil
            guard let current = self.salesLogButtonCenterY() else {
                return nil
            }
            return current - anchor
        }

        func rangeChanged(by chart: ComponentView<Empty>, fraction: ClosedRange<CGFloat>) {
            self.fraction = fraction
            // The other chart follows directly; its date title lives inside the chart, nothing else on the screen depends on the range,
            // so no update of the statistics (or of the sheet around them) per move. `fraction` keeps the range for later updates.
            let other = chart === self.priceChart ? self.salesChart : self.priceChart
            (other.view as? GiftStatsChartComponent.View)?.setVisibleRange(fraction, animated: false)
        }

        /// Top to bottom, in reveal order.
        var revealViews: [UIView] {
            let views: [UIView?] = [self.title.view, self.subtitle.view] + self.tiles + [
                self.itemHeader.view, self.itemPanel, self.itemRow,
                self.salesLogHeader.view, self.salesLogPanel, self.salesLog.view,
                self.priceHeader.view, self.pricePanel, self.priceChart.view,
                self.salesHeader.view, self.salesPanel, self.salesChart.view
            ]
            return views.compactMap { $0 }.filter { $0.superview != nil }
        }

        func scrolled(offset: CGFloat) {
            self.scrollOffset = offset
            self.playVisibleIntros()
        }

        /// Lines start at 40% on screen; bars at half the plot above the "Buy" fade, so the rise is seen. Waits while the card morphs.
        func playVisibleIntros() {
            guard let window = self.window, self.component?.labelsGate.isHidden != true else {
                return
            }
            for chart in [self.priceChart, self.salesChart] {
                guard let chartView = chart.view as? GiftStatsChartComponent.View, !chartView.hasPlayedIntro else {
                    continue
                }
                if chartView.component?.type == .bars {
                    guard let visible = self.component?.viewport(), let plot = chartView.plotFrame else {
                        continue
                    }
                    let frame = chartView.convert(plot, to: self)
                    let shown = frame.intersection(visible)
                    if !shown.isNull && shown.height >= frame.height * 0.5 {
                        chartView.playIntro()
                    }
                } else {
                    let frame = chartView.convert(chartView.bounds, to: window)
                    let shown = frame.intersection(window.bounds)
                    if !shown.isNull && shown.height > frame.height * 0.4 {
                        chartView.playIntro()
                    }
                }
            }
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, transition: transition)
    }
}
