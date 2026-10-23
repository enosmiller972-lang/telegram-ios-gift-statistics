//
//  BaseChartController.swift
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


enum BaseConstants {
    static let defaultRange: ClosedRange<CGFloat> = 0...1
    static let minimumAxisYLabelsDistance: CGFloat = 85
    static let monthDayDateFormatter = DateFormatter.utc(format: "MMM d")
    static let timeDateFormatter = DateFormatter.utc(format: "HH:mm")
    static let headerFullRangeFormatter: DateFormatter = {
        let formatter = DateFormatter.utc()
        formatter.calendar = Calendar.utc
        formatter.dateStyle = .long
        return formatter
    }()
    static let headerMediumRangeFormatter: DateFormatter = {
        let formatter = DateFormatter.utc()
        formatter.dateStyle = .medium
        return formatter
    }()
    static let headerFullZoomedFormatter: DateFormatter = {
        let formatter = DateFormatter.utc()
        formatter.dateStyle = .full
        return formatter
    }()

    static let verticalBaseAnchors: [CGFloat] = [8, 5, 2.5, 2, 1]
    static let defaultVerticalBaseAnchor: CGFloat = 1

    static let mainChartLineWidth: CGFloat = 2
    static let previewChartLineWidth: CGFloat = 1

    static let previewLinesChartOptimizationLevel: CGFloat = 1.5
    static let linesChartOptimizationLevel: CGFloat = 1.0
    static let barsChartOptimizationLevel: CGFloat = 0.75

    static let defaultRangePresetLength = TimeInterval.day * 60
    
    static let chartNumberFormatter: ScalesNumberFormatter = {
        let numberFormatter = ScalesNumberFormatter()
        numberFormatter.allowsFloats = true
        numberFormatter.numberStyle = .decimal
        numberFormatter.usesGroupingSeparator = true
        numberFormatter.groupingSeparator = " "
        numberFormatter.minimumIntegerDigits = 1
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.maximumFractionDigits = 2
        return numberFormatter
    }()
    
    static let tonNumberFormatter: NumberFormatter = {
        let numberFormatter = TonNumberFormatter()
        numberFormatter.allowsFloats = true
        numberFormatter.numberStyle = .decimal
        numberFormatter.usesGroupingSeparator = true
        numberFormatter.groupingSeparator = " "
        numberFormatter.minimumIntegerDigits = 1
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.maximumFractionDigits = 2
        return numberFormatter
    }()
    
    static let starNumberFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.allowsFloats = true
        numberFormatter.numberStyle = .decimal
        numberFormatter.usesGroupingSeparator = true
        numberFormatter.groupingSeparator = " "
        numberFormatter.minimumIntegerDigits = 1
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.maximumFractionDigits = 2
        return numberFormatter
    }()
    
    static let detailsNumberFormatter: NumberFormatter = {
        let detailsNumberFormatter = NumberFormatter()
        detailsNumberFormatter.allowsFloats = false
        detailsNumberFormatter.numberStyle = .decimal
        detailsNumberFormatter.usesGroupingSeparator = true
        detailsNumberFormatter.groupingSeparator = " "
        return detailsNumberFormatter
    }()
}

public class BaseChartController: ChartThemeContainer {
    //let performanceRenderer = PerformanceRenderer()
    var initialChartsCollection: ChartsCollection
    var isZoomed: Bool = false
    public var isZoomable: Bool = true

    var chartTitle: String = ""
    
    public init(chartsCollection: ChartsCollection) {
        self.initialChartsCollection = chartsCollection
    }
        
    public var mainChartRenderers: [ChartViewRenderer] {
        fatalError("Abstract")
    }
    
    public var navigationRenderers: [ChartViewRenderer] {
        fatalError("Abstract")
    }
    
    public var cartViewBounds: (() -> CGRect) = { fatalError() }
    public var chartFrame: (() -> CGRect) = { fatalError() }
    
    public func initializeChart() {
        fatalError("Abstract")
    }
    
    public func chartInteractionDidBegin(point: CGPoint, manual: Bool = true) {
        fatalError("Abstract")
    }
    
    public func chartInteractionDidEnd() {
        fatalError("Abstract")
    }
    
    public func cancelChartInteraction() {
        fatalError("Abstract")
    }
    
    public func didTapZoomOut() {
        fatalError("Abstract")
    }
    
    public func updateChartsVisibility(visibility: [Bool], animated: Bool) {
        fatalError("Abstract")
    }
    
    public var currentHorizontalRange: ClosedRange<CGFloat> {
        fatalError("Abstract")
    }
    
    public func height(for width: CGFloat) -> CGFloat {
        var height: CGFloat = 308
        
        let items = actualChartsCollection.chartValues.map { value in
            return ChartVisibilityItem(title: value.name, color: value.color)
        }
        let frames = ChartVisibilityItem.generateItemsFrames(for: width, items: items)
        
        guard let lastFrame = frames.last else { return height }
        
        height += lastFrame.maxY
        
        return height
    }
    
    public struct ChartSelectionInfo {
        public var index: Int
        public var date: Date
        public var values: [Double]
        public var names: [String]
        public var colors: [GColor]
        /// Finger position along the plot, 0...1 of its width.
        public var fingerFraction: CGFloat
        /// False when the finger moved but the nearest point is the same.
        public var isNewPoint: Bool
        /// Set for a bar that groups several days: `date` is the first day, `values` are sums.
        public var endDate: Date? = nil

        public init(index: Int, date: Date, values: [Double], names: [String], colors: [GColor], fingerFraction: CGFloat, isNewPoint: Bool, endDate: Date? = nil) {
            self.index = index
            self.date = date
            self.values = values
            self.names = names
            self.colors = colors
            self.fingerFraction = fingerFraction
            self.isNewPoint = isNewPoint
            self.endDate = endDate
        }
    }

    /// Localized date range title for gift-style charts; other charts keep their own formatter.
    public static var giftRangeTitle: ((Date, Date) -> String)?

    /// Must be set before the chart is shown (`ChartNode.setup(controller:)` sets it from `ChartNode.giftStyle`).
    public var giftStyle: Bool = false {
        didSet {
            self.giftStyleDidChange()
        }
    }

    func giftStyleDidChange() {
    }

    public func pulseLastPoint() {
    }

    /// Draws only the left `progress` of the plot width with a dot at the stroke head; nil draws everything.
    public func setPlotReveal(_ progress: CGFloat?) {
    }

    /// Point of the currently drawn curve at `x` (chart view coordinates, clamped to the curve); nil if nothing was drawn.
    public func giftCurvePoint(lineIndex: Int, x: CGFloat) -> CGPoint? {
        return nil
    }

    public struct ChartPlotGeometry {
        public var chartFrame: CGRect
        public var horizontalRange: ClosedRange<CGFloat>
        public var verticalRange: ClosedRange<CGFloat>
    }

    /// When set, the chart doesn't draw its own selection and reports it here instead; nil when the selection ends.
    public var selectionHandler: ((ChartSelectionInfo?) -> Void)?

    public var plotGeometry: ChartPlotGeometry? {
        return nil
    }

    /// Moves value labels into a gutter right of the plot (see `ChartNode.setValueGutter`).
    public func setValueLabelsInGutter(_ inGutter: Bool) {
    }

    public func setAreaFill(_ visible: Bool, animated: Bool) {
    }

    public func growBars(delay: TimeInterval) {
    }

    public var valueFormat: ChartValueFormat?

    /// Morphs the shown chart to new data. Returns false (keeping the old data) if the controller can't.
    public func replaceChartsCollection(_ collection: ChartsCollection, animated: Bool) -> Bool {
        return false
    }

    /// Programmatic range change; also moves the range slider via `chartRangeUpdatedClosure`.
    public func setChartRange(_ rangeFraction: ClosedRange<CGFloat>, animated: Bool) {
        self.updateChartRange(rangeFraction, animated: animated)
        self.chartRangeUpdatedClosure?(rangeFraction, animated)
    }

    public var isChartRangePagingEnabled: Bool = false
    public var minimumSelectedChartRange: CGFloat = 0.085
    public var chartRangePagingClosure: ((Bool, CGFloat) -> Void)? // isEnabled, PageSize
    public func setChartRangePagingEnabled(isEnabled: Bool, minimumSelectionSize: CGFloat) {
        isChartRangePagingEnabled = isEnabled
        minimumSelectedChartRange = minimumSelectionSize
        chartRangePagingClosure?(isChartRangePagingEnabled, minimumSelectedChartRange)
    }
    
    public var chartRangeUpdatedClosure: ((ClosedRange<CGFloat>, Bool) -> Void)?
    public var currentChartHorizontalRangeFraction: ClosedRange<CGFloat> {
        fatalError("Abstract")
    }
    
    public func updateChartRange(_ rangeFraction: ClosedRange<CGFloat>, animated: Bool = true) {
        fatalError("Abstract")
    }
    
    public var actualChartVisibility: [Bool] {
        fatalError("Abstract")
    }
    
    public var actualChartsCollection: ChartsCollection {
        fatalError("Abstract")
    }
    
    public var drawChartVisibity: Bool {
        return true
    }

    public var drawChartNavigation: Bool {
        return true
    }
    
    public var setDetailsViewPositionClosure: ((CGFloat) -> Void)?
    public var setDetailsChartVisibleClosure: ((Bool, Bool) -> Void)?
    public var setDetailsViewModel: ((ChartDetailsViewModel, Bool, Bool) -> Void)?
    public var getDetailsData: ((Date, @escaping (ChartsCollection?) -> Void) -> Void)?
    public var setChartTitleClosure: ((String, Bool) -> Void)?
    public var setBackButtonVisibilityClosure: ((Bool, Bool) -> Void)?
    public var refreshChartToolsClosure: ((Bool) -> Void)?

    public func didTapZoomIn(date: Date, pointIndex: Int) {
        fatalError("Abstract")
    }
    
    public func apply(theme: ChartTheme, strings: ChartStrings, animated: Bool) {
        
    }
}
