import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramCore
import TelegramPresentationData
import GraphCore
import GraphUI
import GiftStats
import TelegramStringFormatting

/// The chart only moves to `fraction` when `token` changes.
struct GiftStatsChartRange: Equatable {
    var fraction: ClosedRange<CGFloat>
    var token: Int
}

/// `ChartNode` as a component. Updates are applied in place: lines morph, bars cross-fade (the bar chart has no morph).
final class GiftStatsChartComponent: Component {
    static let crossfadeDuration: Double = 0.25
    private static let baseHeight: CGFloat = 361.0
    private static let topInset: CGFloat = 8.0
    private static let bottomInset: CGFloat = 7.0
    private static let drawDuration: Double = 1.15
    static let gutterWidth: CGFloat = 46.0

    let strings: PresentationStrings
    let graph: StatsGraph
    let type: ChartType
    let valueFormat: ChartValueFormat?
    let dateTimeFormat: PresentationDateTimeFormat
    let range: GiftStatsChartRange
    let series: GiftStatsPriceSeries?
    let palette: GiftTonalPalette
    let title: String
    let spokenValue: (Double) -> String
    let formatValue: (Double) -> NSAttributedString
    let userDidChangeRange: (ClosedRange<CGFloat>) -> Void
    /// Hides the labels over the chart while the card morphs.
    let labelsGate: GiftStatsLabelsGate

    init(
        strings: PresentationStrings,
        graph: StatsGraph,
        type: ChartType,
        valueFormat: ChartValueFormat?,
        dateTimeFormat: PresentationDateTimeFormat,
        range: GiftStatsChartRange,
        series: GiftStatsPriceSeries?,
        palette: GiftTonalPalette,
        title: String,
        spokenValue: @escaping (Double) -> String,
        formatValue: @escaping (Double) -> NSAttributedString,
        userDidChangeRange: @escaping (ClosedRange<CGFloat>) -> Void,
        labelsGate: GiftStatsLabelsGate
    ) {
        self.strings = strings
        self.graph = graph
        self.type = type
        self.valueFormat = valueFormat
        self.dateTimeFormat = dateTimeFormat
        self.range = range
        self.series = series
        self.palette = palette
        self.title = title
        self.spokenValue = spokenValue
        self.formatValue = formatValue
        self.userDidChangeRange = userDidChangeRange
        self.labelsGate = labelsGate
    }

    static func ==(lhs: GiftStatsChartComponent, rhs: GiftStatsChartComponent) -> Bool {
        return lhs.graph == rhs.graph && lhs.type == rhs.type && lhs.range == rhs.range
    }

    final class View: UIView {
        let node = ChartNode()
        let overlay = GiftStatsScrubOverlay()
        var component: GiftStatsChartComponent?
        /// VoiceOver position, an index into the data points.
        var spokenIndex: Int?
        var spokenHide: DispatchWorkItem?
        private var currentGraph: StatsGraph?
        private var appliedRangeToken: Int?
        private var legendHeight: CGFloat = 0.0
        private var appliedLabelsHidden = false
        private var labelsGate: GiftStatsLabelsGate?
        private var introLink: CADisplayLink?
        private var introStart: CFTimeInterval = 0.0
        private var introAreaShown = false
        private var introDuration: Double = 1.0
        private(set) var hasPlayedIntro = false
        override init(frame: CGRect) {
            super.init(frame: frame)
            self.clipsToBounds = true
            self.node.userDidChangeRange = { [weak self] in
                guard let self, let component = self.component, let range = self.node.visibleRange else {
                    return
                }
                component.userDidChangeRange(range)
                self.updateAccessibility(component: component)
            }
            self.node.selectionHandler = { [weak self] info in
                self?.selectionChanged(info)
            }
            self.overlay.haptic = {
                HapticFeedback().tap()
            }
            // Selection dots sit on the line as drawn, not on the raw data points.
            self.overlay.curvePoint = { [weak self] line, x in
                return self?.node.giftCurvePoint(lineIndex: line, x: x)
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            self.introLink?.invalidate()
        }

        func applyLabelsHidden(animated: Bool) {
            let hidden = self.labelsGate?.isHidden ?? false
            guard self.appliedLabelsHidden != hidden else {
                return
            }
            self.appliedLabelsHidden = hidden
            let alpha: CGFloat = hidden ? 0.0 : 1.0
            if animated && !GiftStatsEnvironment.reduceMotion {
                UIView.animate(withDuration: 0.15, animations: {
                    self.node.setLabelsAlpha(alpha)
                })
            } else {
                self.node.setLabelsAlpha(alpha)
            }
        }

        /// Snapshot for the morph, with the date range labels shown even while the gate hides them.
        func morphPicture() -> UIView? {
            // On screen with its labels shown, the system snapshot is the same picture without drawing the chart again.
            if !self.appliedLabelsHidden, GiftMorphCapture.isOnScreen(self), let snapshot = self.snapshotView(afterScreenUpdates: false) {
                return snapshot
            }
            self.node.setLabelsAlpha(1.0)
            defer {
                self.node.setLabelsAlpha(self.appliedLabelsHidden ? 0.0 : 1.0)
            }
            return GiftMorphCapture.picture(of: self)
        }

        override func accessibilityIncrement() {
            self.stepAccessibility(by: 1)
        }

        override func accessibilityDecrement() {
            self.stepAccessibility(by: -1)
        }

        func setVisibleRange(_ fraction: ClosedRange<CGFloat>, animated: Bool) {
            self.node.setVisibleRange(fraction, animated: animated)
            if let component = self.component {
                self.updateAccessibility(component: component)
            }
        }

        var visibleRange: ClosedRange<CGFloat>? {
            return self.node.visibleRange
        }

        func selectionChanged(_ info: BaseChartController.ChartSelectionInfo?) {
            guard let component = self.component else {
                return
            }
            var dateText = info.map { stringForDate(date: $0.date, strings: component.strings) } ?? ""
            if let info, let endDate = info.endDate {
                dateText = component.strings.Gift_Stats_DateRange(dateText, stringForDate(date: endDate, strings: component.strings)).string
            }
            self.overlay.update(info: info, geometry: self.node.plotGeometry, series: component.series, format: component.formatValue, dateText: dateText)
        }

        func update(component: GiftStatsChartComponent, availableSize: CGSize, transition: ComponentTransition) -> CGSize {
            let previousComponent = self.component
            self.component = component
            self.overlay.tooltipFlat = component.palette.button
            self.overlay.showsDots = component.type == .lines
            self.overlay.showsGuide = component.type == .lines
            let strings = component.strings
            self.overlay.join = { first, second in
                return GiftStatsFormat.join(first, second, attributes: [.font: GiftStatsScrubOverlay.valueFont, .foregroundColor: GiftStatsScrubOverlay.valueColor], strings: strings)
            }
            BaseChartController.giftRangeTitle = { from, to in
                return strings.Gift_Stats_DateRange(stringForDate(date: from, strings: strings), stringForDate(date: to, strings: strings)).string
            }
            let animated: Bool
            if case .none = transition.animation {
                animated = false
            } else {
                animated = !GiftStatsEnvironment.reduceMotion
            }

            if previousComponent == nil {
                self.node.giftStyle = true
                let theme = GiftStatsLook.theme
                self.node.setup(theme: ChartTheme(presentationTheme: theme, backgroundColor: UIColor(white: 1.0, alpha: 0.0), rangeViewTintColor: UIColor(white: 0.0, alpha: 0.08), labelsColor: GiftStatsContrast.legible(UIColor(white: 1.0, alpha: 0.72), over: [component.palette.panel])), strings: ChartStrings(
                    zoomOut: component.strings.Stats_ZoomOut,
                    total: component.strings.Stats_Total,
                    revenueInTon: component.strings.Stats_RevenueInTon,
                    revenueInStars: component.strings.Stats_RevenueInStars,
                    revenueInUsd: component.strings.Stats_RevenueInUsd
                ))
            }

            if case let .Loaded(_, data) = component.graph, component.series != nil, self.currentGraph != component.graph {
                if self.currentGraph == nil {
                    self.setupChart(data: data, component: component, width: availableSize.width)
                } else {
                    self.replaceChart(data: data, animated: animated, component: component)
                }
                self.currentGraph = component.graph
            }
            if self.appliedRangeToken != component.range.token {
                let firstTime = self.appliedRangeToken == nil
                self.appliedRangeToken = component.range.token
                self.node.setVisibleRange(component.range.fraction, animated: animated && !firstTime)
            }
            self.hideSingleSeriesLegend()
            if self.labelsGate !== component.labelsGate {
                self.labelsGate = component.labelsGate
                component.labelsGate.add(self)
            }
            self.applyLabelsHidden(animated: false)
            self.updateAccessibility(component: component)
            let size = CGSize(width: availableSize.width, height: GiftStatsChartComponent.baseHeight + self.legendHeight + GiftStatsChartComponent.topInset + GiftStatsChartComponent.bottomInset)
            // Taller than shown and clipped, as in the stats list item.
            self.node.frame = CGRect(origin: CGPoint(x: 0.0, y: GiftStatsChartComponent.topInset), size: CGSize(width: size.width, height: 750.0))
            self.overlay.frame = CGRect(origin: CGPoint(x: 0.0, y: GiftStatsChartComponent.topInset), size: CGSize(width: size.width, height: 310.0))
            return size
        }

        /// A single-series chart has no legend room, so its lone chip would show as a clipped cap under the panel.
        private func hideSingleSeriesLegend() {
            guard self.legendHeight == 0.0 else {
                return
            }
            func hide(_ view: UIView) {
                if String(describing: Swift.type(of: view)) == "ChartVisibilityView" {
                    view.isHidden = true
                    return
                }
                for subview in view.subviews {
                    hide(subview)
                }
            }
            hide(self.node.view)
        }

        private func setupChart(data: String, component: GiftStatsChartComponent, width: CGFloat) {
            guard let controller = createChartController(data, type: component.type, valueFormat: component.valueFormat, getDetailsData: { _, completion in
                completion(nil)
            }) else {
                return
            }
            self.legendHeight = GiftStatsChartComponent.legendHeight(controller: controller, width: width)
            self.node.setup(controller: controller, noInitialZoom: true)
            self.node.setValueGutter(GiftStatsChartComponent.gutterWidth)
            if self.node.view.superview == nil {
                self.addSubview(self.node.view)
                self.addSubview(self.overlay)
            }
            // Empty until `playIntro`.
            if component.type == .lines {
                self.node.setPlotReveal(0.0)
                self.node.setAreaFill(false, animated: false)
            } else if !GiftStatsEnvironment.reduceMotion {
                self.node.growBars(delay: .infinity)
            }
        }

        private func replaceChart(data: String, animated: Bool, component: GiftStatsChartComponent) {
            var snapshot: UIView?
            if component.type == .bars, animated {
                snapshot = self.snapshotView(afterScreenUpdates: false)
            }
            self.node.replaceData(data, animated: animated)
            if let snapshot {
                snapshot.frame = self.bounds
                self.addSubview(snapshot)
                UIView.animate(withDuration: GiftStatsChartComponent.crossfadeDuration, delay: 0.0, options: [.curveEaseInOut], animations: {
                    snapshot.alpha = 0.0
                }, completion: { _ in
                    snapshot.removeFromSuperview()
                })
            }
        }

        /// The plot area only, without the date labels and the range slider.
        var plotFrame: CGRect? {
            self.node.view.layoutIfNeeded()
            guard let frame = self.node.plotGeometry?.chartFrame, frame.height > 1.0 else {
                return nil
            }
            return frame.offsetBy(dx: self.node.frame.minX, dy: self.node.frame.minY)
        }

        func playIntro() {
            guard let component = self.component, !self.hasPlayedIntro else {
                return
            }
            self.hasPlayedIntro = true
            if component.type == .bars {
                if !GiftStatsEnvironment.reduceMotion {
                    self.node.growBars(delay: 0.0)
                }
                return
            }
            if GiftStatsEnvironment.reduceMotion {
                self.node.setPlotReveal(nil)
                self.node.setAreaFill(true, animated: true)
                return
            }
            self.startReveal(component: component, duration: GiftStatsChartComponent.drawDuration)
        }

        private func startReveal(component: GiftStatsChartComponent, duration: Double) {
            self.introAreaShown = false
            self.introDuration = duration
            self.introStart = CACurrentMediaTime()
            self.introLink?.invalidate()
            let link = CADisplayLink(target: self, selector: #selector(self.introTick))
            link.add(to: .main, forMode: .common)
            self.introLink = link
        }

        @objc private func introTick() {
            let elapsed = CACurrentMediaTime() - self.introStart
            let t = min(1.0, elapsed / self.introDuration)
            let eased = t < 0.5 ? 4.0 * t * t * t : 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0
            // The renderer draws the head dot at the cut in the same frame (`LinesChartRenderer.drawGiftDot`).
            self.node.setPlotReveal(CGFloat(eased))
            if !self.introAreaShown, t > 0.6 {
                self.introAreaShown = true
                self.node.setAreaFill(true, animated: true)
            }
            if t >= 1.0 {
                self.node.setPlotReveal(nil)
                self.introLink?.invalidate()
                self.introLink = nil
                self.node.pulseLastPoint()
            }
        }
    }

    private static func legendHeight(controller: BaseChartController, width: CGFloat) -> CGFloat {
        let items = controller.actualChartsCollection.chartValues.map { ChartVisibilityItem(title: $0.name, color: .black) }
        guard items.count > 1 else {
            return 0.0
        }
        return calculateVisiblityHeight(width: width, items: items)
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, transition: transition)
    }
}
