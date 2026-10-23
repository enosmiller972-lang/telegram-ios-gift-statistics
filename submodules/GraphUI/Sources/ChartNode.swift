import Foundation
import UIKit
import SwiftSignalKit
import Display
import AsyncDisplayKit
import AppBundle
import GraphCore
import TelegramPresentationData

public enum ChartType {
    case lines
    case twoAxis
    case pie
    case area
    case bars
    case step
    case twoAxisStep
    case hourlyStep
    case twoAxisHourlyStep
    case twoAxis5MinStep
    case currency
    case stars
    case lines5Min
}

public extension ChartTheme {    
    convenience init(presentationTheme: PresentationTheme, backgroundColor: UIColor? = nil, rangeViewTintColor: UIColor? = nil, labelsColor: UIColor? = nil) {
        let rangeViewFrameColor = presentationTheme.chart.rangeViewFrameColor
        let rangeViewMarkerColor = presentationTheme.chart.rangeViewMarkerColor
        
        let rangeImage = generateImage(CGSize(width: 114.0, height: 42.0), rotatedContext: { size, context in
            let bounds = CGRect(origin: CGPoint(), size: size)
            context.clear(bounds)
            
            context.setFillColor(rangeViewFrameColor.cgColor)
            var path = UIBezierPath.init(roundedRect: CGRect(x: 0.0, y: 0.0, width: 11.0, height: 42.0), byRoundingCorners: [.topLeft, .bottomLeft], cornerRadii: CGSize(width: 6.0, height: 6.0))
            context.addPath(path.cgPath)
            context.fillPath()
            
            path = UIBezierPath.init(roundedRect: CGRect(x: 103.0, y: 0.0, width: 11.0, height: 42.0), byRoundingCorners: [.topRight, .bottomRight], cornerRadii: CGSize(width: 6.0, height: 6.0))
            context.addPath(path.cgPath)
            context.fillPath()
            
            context.setFillColor(rangeViewFrameColor.cgColor)
            context.fill(CGRect(x: 7.0, y: 0.0, width: 4.0, height: 1.0))
            context.fill(CGRect(x: 7.0, y: 41.0, width: 4.0, height: 1.0))
            
            context.fill(CGRect(x: 100.0, y: 0.0, width: 4.0, height: 1.0))
            context.fill(CGRect(x: 100.0, y: 41.0, width: 4.0, height: 1.0))
            
            context.fill(CGRect(x: 11.0, y: 0.0, width: 92.0, height: 1.0))
            context.fill(CGRect(x: 11.0, y: 41.0, width: 92.0, height: 1.0))
            
            context.setLineCap(.round)
            context.setLineWidth(1.5)
            context.setStrokeColor(rangeViewMarkerColor.cgColor)
            context.move(to: CGPoint(x: 7.0, y: 17.0))
            context.addLine(to: CGPoint(x: 4.0, y: 21.0))
            context.addLine(to: CGPoint(x: 7.0, y: 25.0))
            context.strokePath()
            
            context.move(to: CGPoint(x: 107.0, y: 17.0))
            context.addLine(to: CGPoint(x: 110.0, y: 21.0))
            context.addLine(to: CGPoint(x: 107.0, y: 25.0))
            context.strokePath()
        })?.resizableImage(withCapInsets: UIEdgeInsets(top: 15.0, left: 11.0, bottom: 15.0, right: 11.0), resizingMode: .stretch)
        
        self.init(chartTitleColor: presentationTheme.list.itemPrimaryTextColor, actionButtonColor: presentationTheme.list.itemAccentColor, chartBackgroundColor: backgroundColor ?? presentationTheme.list.itemBlocksBackgroundColor, chartLabelsColor: labelsColor ?? presentationTheme.chart.labelsColor, chartHelperLinesColor: presentationTheme.chart.helperLinesColor, chartStrongLinesColor: presentationTheme.chart.strongLinesColor, barChartStrongLinesColor: presentationTheme.chart.barStrongLinesColor, chartDetailsTextColor: presentationTheme.chart.detailsTextColor, chartDetailsArrowColor: presentationTheme.chart.detailsArrowColor, chartDetailsViewColor: presentationTheme.chart.detailsViewColor, rangeViewFrameColor: rangeViewFrameColor, rangeViewTintColor: rangeViewTintColor ?? presentationTheme.list.blocksBackgroundColor.withAlphaComponent(0.5), rangeViewMarkerColor: rangeViewMarkerColor, rangeCropImage: rangeImage)
    }
}

public func createChartController(_ data: String, type: ChartType, rate: Double = 1.0, valueFormat: ChartValueFormat? = nil, getDetailsData: @escaping (Date, @escaping (String?) -> Void) -> Void) -> BaseChartController? {
    var resultController: BaseChartController?
    if let data = data.data(using: .utf8) {
        ChartsDataManager.readChart(data: data, extraCopiesCount: 0, sync: true, success: { collection in
            let controller: BaseChartController
            switch type {
                case .lines:
                    controller = GeneralLinesChartController(chartsCollection: collection)
                    controller.isZoomable = false
                case .twoAxis:
                    controller = TwoAxisLinesChartController(chartsCollection: collection)
                    controller.isZoomable = false
                case .pie:
                    controller = PercentPieChartController(chartsCollection: collection, initiallyZoomed: true)
                case .area:
                    controller = PercentPieChartController(chartsCollection: collection, initiallyZoomed: false)
                case .bars:
                    controller = StackedBarsChartController(chartsCollection: collection)
                    controller.isZoomable = false
                case .currency:
                    var iconCache: [UInt32: UIImage] = [:]
                    controller = StackedBarsChartController(chartsCollection: collection, currency: .ton, drawCurrency: { context, color, point in
                        let icon: UIImage?
                        if let current = iconCache[color.rgb] {
                            icon = current
                        } else if let image = generateTintedImage(image: UIImage(bundleImageName: "Ads/Ton"), color: color) {
                            icon = generateImage(image.size, rotatedContext: { size, context in
                                context.clear(CGRect(origin: .zero, size: size))
                                if let cgImage = image.cgImage {
                                    context.draw(cgImage, in: CGRect(origin: .zero, size: size), byTiling: false)
                                }
                            })
                            iconCache[color.rgb] = icon
                        } else {
                            icon = nil
                        }
                        if let icon, let cgImage = icon.cgImage {
                            context.draw(cgImage, in: CGRect(origin: point.offsetBy(dx: 0.0, dy: -2.0), size: icon.size), byTiling: false)
                        }
                    }, rate: rate)
                    controller.isZoomable = false
                case .stars:
                    var icon: UIImage?
                    if let image = UIImage(bundleImageName: "Premium/Stars/StarSmall") {
                        icon = generateImage(CGSize(width: floor(image.size.width * 0.82), height: floor(image.size.width * 0.82)), rotatedContext: { size, context in
                            context.clear(CGRect(origin: .zero, size: size))
                            if let cgImage = image.cgImage {
                                context.draw(cgImage, in: CGRect(origin: .zero, size: size), byTiling: false)
                            }
                        })
                    }
                    controller = StackedBarsChartController(chartsCollection: collection, currency: .xtr, drawCurrency: { context, color, point in
                        if let icon, let cgImage = icon.cgImage {
                            context.draw(cgImage, in: CGRect(origin: point.offsetBy(dx: -3.0, dy: -4.0), size: icon.size), byTiling: false)
                        }
                    }, rate: rate)
                    controller.isZoomable = false
                case .step:
                    controller = StepBarsChartController(chartsCollection: collection)
                case .twoAxisStep:
                    controller = TwoAxisStepBarsChartController(chartsCollection: collection)
                case .hourlyStep:
                    controller = StepBarsChartController(chartsCollection: collection, hourly: true)
                    controller.isZoomable = false
                case .twoAxisHourlyStep:
                    let stepController = TwoAxisStepBarsChartController(chartsCollection: collection)
                    stepController.hourly = true
                    controller = stepController
                    controller.isZoomable = false
                case .twoAxis5MinStep:
                    let stepController = TwoAxisStepBarsChartController(chartsCollection: collection)
                    stepController.min5 = true
                    controller = stepController
                    controller.isZoomable = false
                case .lines5Min:
                    let linesController = GeneralLinesChartController(chartsCollection: collection)
                    linesController.min5 = true
                    controller = linesController
                    controller.isZoomable = false
            }
            controller.valueFormat = valueFormat
            controller.getDetailsData = { date, completion in
                getDetailsData(date, { detailsData in
                    if let detailsData = detailsData, let data = detailsData.data(using: .utf8) {
                        ChartsDataManager.readChart(data: data, extraCopiesCount: 0, sync: true, success: { collection in
                            Queue.mainQueue().async {
                                completion(collection)
                            }
                        }) { error in
                            completion(nil)
                        }
                    } else {
                        completion(nil)
                    }
                })
            }
            resultController = controller
        }) { error in
            
        }
    }
    return resultController
}

public final class ChartNode: ASDisplayNode {
    private var chartView: ChartStackSection {
        return self.view as! ChartStackSection
    }
    
    public override init() {
        super.init()
        
        self.setViewBlock({
            return ChartStackSection()
        })
    }
        
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func setup(theme: ChartTheme, strings: ChartStrings) {
        self.chartView.apply(theme: theme, strings: strings, animated: false)
    }
    
    /// See `BaseChartController.selectionHandler`.
    public var selectionHandler: ((BaseChartController.ChartSelectionInfo?) -> Void)? {
        didSet {
            self.chartView.controller?.selectionHandler = self.selectionHandler
        }
    }
    
    /// Plot frame in this node's coordinates and the data ranges currently shown.
    public var plotGeometry: BaseChartController.ChartPlotGeometry? {
        return self.chartView.controller?.plotGeometry
    }
    
    /// Reserves `width` right of the plot for the value labels so they never overlap the data.
    public func setValueGutter(_ width: CGFloat) {
        self.chartView.chartView.chartInsets.right = 16.0 + width
        self.chartView.controller?.setValueLabelsInGutter(width > 0.0)
        self.chartView.chartView.setNeedsDisplay()
    }
    
    /// Gift statistics look. Set before `setup(controller:)`.
    public var giftStyle: Bool = false {
        didSet {
            self.chartView.giftStyle = self.giftStyle
        }
    }
    
    /// Alpha of the date range title above the plot.
    public func setLabelsAlpha(_ alpha: CGFloat) {
        self.chartView.titleLabel.alpha = alpha
    }

    public func pulseLastPoint() {
        self.chartView.controller?.pulseLastPoint()
    }
    
    public func setAreaFill(_ visible: Bool, animated: Bool) {
        self.chartView.controller?.setAreaFill(visible, animated: animated)
    }
    
    /// Bars stay flat for `delay` seconds, then grow from the baseline.
    public func growBars(delay: TimeInterval) {
        self.chartView.controller?.growBars(delay: delay)
    }
    
    /// Line draw-in: the renderer cuts the stroke at `progress`, a mask reveals grid and labels slightly ahead. Nil shows all.
    public func setPlotReveal(_ progress: CGFloat?) {
        self.chartView.setPlotReveal(progress)
        self.chartView.controller?.setPlotReveal(progress)
    }

    /// See `BaseChartController.giftCurvePoint`; in this node's coordinates.
    public func giftCurvePoint(lineIndex: Int, x: CGFloat) -> CGPoint? {
        return self.chartView.controller?.giftCurvePoint(lineIndex: lineIndex, x: x)
    }
    
    public func setup(controller: BaseChartController, noInitialZoom: Bool = false) {
        controller.selectionHandler = self.selectionHandler
        controller.giftStyle = self.giftStyle
        var displayRange = true
        var zoomToEnding = true
        if let controller = controller as? StepBarsChartController {
            displayRange = !controller.hourly
        }
        if noInitialZoom {
            zoomToEnding = false
        }
        self.chartView.setup(controller: controller, displayRange: displayRange, zoomToEnding: zoomToEnding)
    }
    
    public func resetInteraction() {
        self.chartView.resetDetailsView()
    }
    
    /// Called only for user interaction with the range slider.
    public var userDidChangeRange: (() -> Void)? {
        get {
            return self.chartView.userDidChangeRange
        }
        set {
            self.chartView.userDidChangeRange = newValue
        }
    }
    
    /// Same JSON as `createChartController`. Returns false and keeps the old data if the current chart can't show it.
    @discardableResult
    public func replaceData(_ data: String, animated: Bool) -> Bool {
        guard let controller = self.chartView.controller, let jsonData = data.data(using: .utf8) else {
            return false
        }
        var replaced = false
        ChartsDataManager.readChart(data: jsonData, extraCopiesCount: 0, sync: true, success: { collection in
            replaced = controller.replaceChartsCollection(collection, animated: animated)
        }, failure: { _ in
        })
        return replaced
    }
    
    /// 0...1 is the whole data.
    public var visibleRange: ClosedRange<CGFloat>? {
        return self.chartView.controller?.currentChartHorizontalRangeFraction
    }
    
    public var seriesNames: [String] {
        return self.chartView.controller?.actualChartsCollection.chartValues.map { $0.name } ?? []
    }
    
    /// Also moves the range slider. 0...1 is the whole data.
    public func setVisibleRange(_ fraction: ClosedRange<CGFloat>, animated: Bool) {
        self.chartView.controller?.setChartRange(fraction, animated: animated)
    }
}
