//
//  LinesChartController.swift
//  GraphTest
//
//  Created by Andrei Salavei on 4/7/19.
//  Copyright © 2019 Andrei Salavei. All rights reserved.
//

import Foundation
#if os(macOS)
import Cocoa
#else
import UIKit
#endif

private enum Constants {
    static let defaultRange: ClosedRange<CGFloat> = 0...1
}

public class GeneralLinesChartController: BaseLinesChartController {
    private var initialChartCollection: ChartsCollection

    private let mainLinesRenderer = LinesChartRenderer()
    private let horizontalScalesRenderer = HorizontalScalesRenderer()
    private let verticalScalesRenderer = VerticalScalesRenderer()
    private let verticalLineRenderer = VerticalLinesRenderer()
    private let lineBulletsRenderer = LineBulletsRenderer()

    private let previewLinesRenderer = LinesChartRenderer()

    private var totalVerticalRange: ClosedRange<CGFloat> = Constants.defaultRange
    private var totalHorizontalRange: ClosedRange<CGFloat> = Constants.defaultRange
    
    private var prevoiusHorizontalStrideInterval: Int = 1
    
    private(set) var chartLines: [LinesChartRenderer.LineData] = []
    
    public var min5 = false

    /// Widens a zero-width range (single point or flat line) by one unit, since the chart divides by range widths.
    private static func nonEmpty(_ range: ClosedRange<CGFloat>) -> ClosedRange<CGFloat> {
        guard range.lowerBound.isFinite, range.upperBound.isFinite else {
            return Constants.defaultRange
        }
        return range.upperBound - range.lowerBound > 0.0 ? range : range.lowerBound ... (range.upperBound + 1.0)
    }

    override public init(chartsCollection: ChartsCollection)  {
        self.initialChartCollection = chartsCollection
        self.mainLinesRenderer.lineWidth = 2
        self.mainLinesRenderer.optimizationLevel = BaseConstants.linesChartOptimizationLevel
        self.previewLinesRenderer.optimizationLevel = BaseConstants.previewLinesChartOptimizationLevel

        self.lineBulletsRenderer.isEnabled = false

        super.init(chartsCollection: chartsCollection)
        self.zoomChartVisibility = chartVisibility
    }
    
    override func setupChartCollection(chartsCollection: ChartsCollection, animated: Bool, isZoomed: Bool) {
        super.setupChartCollection(chartsCollection: chartsCollection, animated: animated, isZoomed: isZoomed)
        
        self.chartLines = chartsCollection.chartValues.map { chart in
            let points = chart.values.enumerated().map({ (arg) -> CGPoint in
                return CGPoint(x: chartsCollection.axisValues[arg.offset].timeIntervalSince1970,
                               y: arg.element)
            })
            return LinesChartRenderer.LineData(color: chart.color, points: points)
        }
        
        self.prevoiusHorizontalStrideInterval = -1
        self.totalVerticalRange = GeneralLinesChartController.nonEmpty(LinesChartRenderer.LineData.verticalRange(lines: chartLines) ?? Constants.defaultRange)
        self.totalHorizontalRange = GeneralLinesChartController.nonEmpty(LinesChartRenderer.LineData.horizontalRange(lines: chartLines) ?? Constants.defaultRange)
        self.lineBulletsRenderer.bullets = self.chartLines.map { LineBulletsRenderer.Bullet(coordinate: $0.points.first ?? .zero, offset: .zero,
                                                                                          color: $0.color)}

        let chartRange: ClosedRange<CGFloat>
        if isZoomed {
            chartRange = GeneralLinesChartController.nonEmpty(zoomedChartRange)
        } else {
            chartRange = GeneralLinesChartController.nonEmpty(initialChartRange)
        }

        self.previewLinesRenderer.setup(horizontalRange: totalHorizontalRange, animated: animated)
        self.previewLinesRenderer.setup(verticalRange: totalVerticalRange, animated: animated)
        
        self.mainLinesRenderer.setLines(lines: chartLines, animated: animated)
        self.previewLinesRenderer.setLines(lines: chartLines, animated: animated)
        
        updateHorizontalLimits(horizontalRange: chartRange, animated: animated)
        updateMainChartHorizontalRange(range: chartRange, animated: animated)
        updateVerticalLimitsAndRange(horizontalRange: chartRange, animated: animated)
        self.chartRangeUpdatedClosure?(currentChartHorizontalRangeFraction, animated)
    }
    
   public  override func initializeChart() {
        if let first = initialChartCollection.axisValues.first?.timeIntervalSince1970,
            let last = initialChartCollection.axisValues.last?.timeIntervalSince1970 {
            initialChartRange = CGFloat(max(first, last - BaseConstants.defaultRangePresetLength))...CGFloat(last)
        }
        setupChartCollection(chartsCollection: initialChartCollection, animated: false, isZoomed: false)
    }
    
    public override var mainChartRenderers: [ChartViewRenderer] {
        return [//performanceRenderer,
                mainLinesRenderer,
                horizontalScalesRenderer,
                verticalScalesRenderer,
                verticalLineRenderer,
                lineBulletsRenderer
        ]
    }
    
    public override var navigationRenderers: [ChartViewRenderer] {
        return [previewLinesRenderer]
    }
    
    public override func updateChartsVisibility(visibility: [Bool], animated: Bool) {
        chartVisibility = visibility
        zoomChartVisibility = visibility
        for (index, isVisible) in visibility.enumerated() {
            mainLinesRenderer.setLineVisible(isVisible, at: index, animated: animated)
            previewLinesRenderer.setLineVisible(isVisible, at: index, animated: animated)
            lineBulletsRenderer.setLineVisible(isVisible, at: index, animated: animated)
        }
        
        updateVerticalLimitsAndRange(horizontalRange: currentHorizontalRange, animated: true)
     
        if isChartInteractionBegun {
            chartInteractionDidBegin(point: lastChartInteractionPoint, manual: false)
        }
    }

    public override func chartInteractionDidBegin(point: CGPoint, manual: Bool = true) {
        if manual && !isChartInteracting && !self.verticalLineRenderer.values.isEmpty {
            self.cancelChartInteraction()
            ignoreInteraction = true
            return
        }
        let horizontalRange = mainLinesRenderer.horizontalRange.current
        let chartFrame = self.chartFrame()
        guard chartFrame.width > 0 else { return }

        let dateToFind = Date(timeIntervalSince1970: TimeInterval(horizontalRange.distance * point.x + horizontalRange.lowerBound))
        guard let (closestDate, minIndex) = findClosestDateTo(dateToFind: dateToFind) else { return }
        
        let chartInteractionWasBegin = isChartInteractionBegun
        super.chartInteractionDidBegin(point: point)

        if let handler = self.selectionHandler {
            let isNewPoint = self.selectedPointIndex != minIndex
            self.selectedPointIndex = minIndex
            let collection = self.actualChartsCollection
            handler(ChartSelectionInfo(
                index: minIndex,
                date: closestDate,
                values: collection.chartValues.map { $0.values[minIndex] },
                names: collection.chartValues.map { $0.name },
                colors: collection.chartValues.map { $0.color },
                fingerFraction: point.x,
                isNewPoint: isNewPoint
            ))
            return
        }

        self.lineBulletsRenderer.bullets = chartLines.compactMap { chart in
            return LineBulletsRenderer.Bullet(coordinate: chart.points[minIndex], offset: .zero, color: chart.color)
        }
        self.lineBulletsRenderer.isEnabled = true
        
        let chartValue: CGFloat = CGFloat(closestDate.timeIntervalSince1970)
        var chartValueUpdated = true
        if self.verticalLineRenderer.values == [chartValue] {
            chartValueUpdated = false
        }
        let detailsViewPosition = (chartValue - horizontalRange.lowerBound) / horizontalRange.distance * chartFrame.width + chartFrame.minX
        self.setDetailsViewModel?(chartDetailsViewModel(closestDate: closestDate, pointIndex: minIndex, loading: false), chartInteractionWasBegin, chartInteractionWasBegin && chartValueUpdated)
        self.setDetailsChartVisibleClosure?(true, true)
        self.setDetailsViewPositionClosure?(detailsViewPosition)
        self.verticalLineRenderer.values = [chartValue]
    }
    
    
    public override func replaceChartsCollection(_ collection: ChartsCollection, animated: Bool) -> Bool {
        guard collection.chartValues.count == chartVisibility.count, collection.axisValues.count > 1 else {
            return false
        }
        cancelChartInteraction()
        self.initialChartCollection = collection
        // Keep the visible range; setup reads it from `initialChartRange`.
        self.initialChartRange = self.currentHorizontalRange
        self.setupChartCollection(chartsCollection: collection, animated: animated, isZoomed: false)
        return true
    }

    public override func setChartRange(_ rangeFraction: ClosedRange<CGFloat>, animated: Bool) {
        cancelChartInteraction()
        let horizontalRange = ClosedRange(uncheckedBounds:
            (lower: totalHorizontalRange.lowerBound + rangeFraction.lowerBound * totalHorizontalRange.distance,
             upper: totalHorizontalRange.lowerBound + rangeFraction.upperBound * totalHorizontalRange.distance))
        zoomedChartRange = horizontalRange
        updateChartRangeTitle(animated: animated)
        updateMainChartHorizontalRange(range: horizontalRange, animated: animated)
        updateHorizontalLimits(horizontalRange: horizontalRange, animated: animated)
        updateVerticalLimitsAndRange(horizontalRange: horizontalRange, animated: animated)
        self.chartRangeUpdatedClosure?(rangeFraction, animated)
    }

    public override var currentChartHorizontalRangeFraction: ClosedRange<CGFloat> {
        let lowerPercent = (currentHorizontalRange.lowerBound - totalHorizontalRange.lowerBound) / totalHorizontalRange.distance
        let upperPercent = (currentHorizontalRange.upperBound - totalHorizontalRange.lowerBound) / totalHorizontalRange.distance
        return lowerPercent...upperPercent
    }
    
    public override var currentHorizontalRange: ClosedRange<CGFloat> {
        return mainLinesRenderer.horizontalRange.end
    }

    private var selectedPointIndex: Int?

    public override func chartInteractionDidEnd() {
        super.chartInteractionDidEnd()
        if let handler = self.selectionHandler, self.selectedPointIndex != nil {
            self.selectedPointIndex = nil
            handler(nil)
        }
    }

    public override var plotGeometry: ChartPlotGeometry? {
        return ChartPlotGeometry(chartFrame: self.chartFrame(), horizontalRange: self.mainLinesRenderer.horizontalRange.current, verticalRange: self.mainLinesRenderer.verticalRange.current)
    }

    public override func setValueLabelsInGutter(_ inGutter: Bool) {
        self.verticalScalesRenderer.labelsInGutter = inGutter
    }

    override func giftStyleDidChange() {
        let on = self.giftStyle
        self.mainLinesRenderer.giftRole = on ? .main : .off
        self.previewLinesRenderer.giftRole = on ? .preview : .off
        self.verticalScalesRenderer.giftStyle = on
        self.horizontalScalesRenderer.giftStyle = on
    }

    public override func pulseLastPoint() {
        self.mainLinesRenderer.playPulse()
    }

    public override func setPlotReveal(_ progress: CGFloat?) {
        self.mainLinesRenderer.setGiftReveal(progress)
    }

    public override func giftCurvePoint(lineIndex: Int, x: CGFloat) -> CGPoint? {
        return self.mainLinesRenderer.giftCurvePoint(lineIndex: lineIndex, x: x)
    }

    public override func setAreaFill(_ visible: Bool, animated: Bool) {
        self.mainLinesRenderer.setAreaVisible(visible, animated: animated)
    }

    public override func cancelChartInteraction() {
        super.cancelChartInteraction()
        if let handler = self.selectionHandler, self.selectedPointIndex != nil {
            self.selectedPointIndex = nil
            handler(nil)
        }
        self.lineBulletsRenderer.isEnabled = false
        
        self.setDetailsChartVisibleClosure?(false, true)
        self.verticalLineRenderer.values = []
    }
    
    public override func didTapZoomOut() {
        cancelChartInteraction()
        self.setupChartCollection(chartsCollection: initialChartCollection, animated: true, isZoomed: false)
    }
    
    var visibleCharts: [LinesChartRenderer.LineData] {
        let visibleCharts: [LinesChartRenderer.LineData] = chartVisibility.enumerated().compactMap { args in
            args.element ? chartLines[args.offset] : nil
        }
        return visibleCharts
    }
    
    public override func updateChartRange(_ rangeFraction: ClosedRange<CGFloat>, animated: Bool = true) {
        cancelChartInteraction()
        
        let horizontalRange = ClosedRange(uncheckedBounds:
            (lower: totalHorizontalRange.lowerBound + rangeFraction.lowerBound * totalHorizontalRange.distance,
             upper: totalHorizontalRange.lowerBound + rangeFraction.upperBound * totalHorizontalRange.distance))
        
        zoomedChartRange = horizontalRange
        updateChartRangeTitle(animated: animated)

        updateMainChartHorizontalRange(range: horizontalRange, animated: false)
        updateHorizontalLimits(horizontalRange: horizontalRange, animated: animated)
        updateVerticalLimitsAndRange(horizontalRange: horizontalRange, animated: animated)
    }
    
    func updateMainChartHorizontalRange(range: ClosedRange<CGFloat>, animated: Bool) {
        mainLinesRenderer.setup(horizontalRange: range, animated: animated)
        horizontalScalesRenderer.setup(horizontalRange: range, animated: animated)
        verticalScalesRenderer.setup(horizontalRange: range, animated: animated)
        verticalLineRenderer.setup(horizontalRange: range, animated: animated)
        lineBulletsRenderer.setup(horizontalRange: range, animated: animated)
    }

    func updateMainChartVerticalRange(range: ClosedRange<CGFloat>, animated: Bool) {
        mainLinesRenderer.setup(verticalRange: range, animated: animated)
        horizontalScalesRenderer.setup(verticalRange: range, animated: animated)
        verticalScalesRenderer.setup(verticalRange: range, animated: animated)
        verticalLineRenderer.setup(verticalRange: range, animated: animated)
        lineBulletsRenderer.setup(verticalRange: range, animated: animated)
    }
    
    func updateHorizontalLimits(horizontalRange: ClosedRange<CGFloat>, animated: Bool) {
        var scaleType: ChartScaleType = .day
        if self.min5 {
            scaleType = .minutes5
        } else if isZoomed {
            scaleType = .hour
        }
        
        if let (stride, labels) = horizontalLimitsLabels(
            horizontalRange: horizontalRange,
            scaleType: scaleType,
            prevoiusHorizontalStrideInterval: prevoiusHorizontalStrideInterval
        ) {
            self.horizontalScalesRenderer.setup(labels: labels, animated: animated)
            self.prevoiusHorizontalStrideInterval = stride
        }
    }
    
    func updateVerticalLimitsAndRange(horizontalRange: ClosedRange<CGFloat>, animated: Bool) {
        if let verticalRange = LinesChartRenderer.LineData.verticalRange(lines: visibleCharts,
                                                                         calculatingRange: horizontalRange,
                                                                         addBounds: true) {
            
            let (range, labels) = verticalLimitsLabels(verticalRange: verticalRange)
            
            if verticalScalesRenderer.verticalRange.end != range {
                verticalScalesRenderer.setup(verticalLimitsLabels: labels, animated: animated)
                updateMainChartVerticalRange(range: range, animated: animated)
            }
            verticalScalesRenderer.setVisible(true, animated: animated)
        } else {
            verticalScalesRenderer.setVisible(false, animated: animated)
        }
        
        guard let previewVerticalRange = LinesChartRenderer.LineData.verticalRange(lines: visibleCharts) else { return }

        if previewLinesRenderer.verticalRange.end != previewVerticalRange {
            previewLinesRenderer.setup(verticalRange: previewVerticalRange, animated: animated)
        }
    }
    
    override public func apply(theme: ChartTheme, strings: ChartStrings, animated: Bool) {
        horizontalScalesRenderer.labelsColor = theme.chartLabelsColor
        verticalScalesRenderer.labelsColor = theme.chartLabelsColor
        verticalScalesRenderer.axisXColor = theme.chartStrongLinesColor
        verticalScalesRenderer.horizontalLinesColor = theme.chartHelperLinesColor
        lineBulletsRenderer.setInnerColor(theme.chartBackgroundColor, animated: animated)
        verticalLineRenderer.linesColor = theme.chartStrongLinesColor
    }
}
