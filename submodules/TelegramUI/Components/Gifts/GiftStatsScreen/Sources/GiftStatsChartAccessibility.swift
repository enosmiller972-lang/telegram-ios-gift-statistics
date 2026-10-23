import Foundation
import UIKit
import Display
import TelegramPresentationData
import TelegramStringFormatting
import GraphCore
import GiftStats

/// VoiceOver: the chart is one adjustable element; swiping steps through visible points and shows their tooltip.
extension GiftStatsChartComponent.View {
    private func visiblePoints(series: GiftStatsPriceSeries) -> [Int] {
        guard let first = series.times.first, let last = series.times.last else {
            return []
        }
        let fraction = self.visibleRange ?? (0.0 ... 1.0)
        let lower = first + Double(fraction.lowerBound) * (last - first)
        let upper = first + Double(fraction.upperBound) * (last - first)
        let slack = max(1.0, (upper - lower) * 0.001)
        return series.times.indices.filter { series.times[$0] >= lower - slack && series.times[$0] <= upper + slack }
    }

    private func dateText(_ time: Double, strings: PresentationStrings) -> String {
        return stringForDate(date: Date(timeIntervalSince1970: time), strings: strings)
    }

    func updateAccessibility(component: GiftStatsChartComponent) {
        guard let series = component.series else {
            self.isAccessibilityElement = false
            return
        }
        let strings = component.strings
        self.isAccessibilityElement = true
        self.accessibilityTraits = .adjustable
        let points = self.visiblePoints(series: series)
        guard let firstIndex = points.first, let lastIndex = points.last else {
            self.accessibilityLabel = component.title
            self.accessibilityValue = nil
            return
        }
        let range = strings.Gift_Stats_DateRange(self.dateText(series.times[firstIndex], strings: strings), self.dateText(series.times[lastIndex], strings: strings)).string
        self.accessibilityLabel = GiftStatsFormat.join(component.title, range, strings: strings)
        if let index = self.spokenIndex, points.contains(index) {
            self.accessibilityValue = self.spokenPoint(index, series: series, component: component)
            return
        }
        self.spokenIndex = nil
        let values = series.values
        if component.type == .lines {
            self.accessibilityValue = strings.Gift_Stats_FromTo(component.spokenValue(values[firstIndex]), component.spokenValue(values[lastIndex])).string
        } else {
            let total = points.reduce(0.0) { $0 + values[$1] }
            self.accessibilityValue = GiftStatsFormat.join(strings.Stats_Total, component.spokenValue(total), strings: strings)
        }
    }

    private func spokenPoint(_ index: Int, series: GiftStatsPriceSeries, component: GiftStatsChartComponent) -> String {
        return GiftStatsFormat.join(self.dateText(series.times[index], strings: component.strings), component.spokenValue(series.values[index]), strings: component.strings)
    }

    func stepAccessibility(by delta: Int) {
        guard let component = self.component, let series = component.series else {
            return
        }
        let points = self.visiblePoints(series: series)
        guard !points.isEmpty else {
            return
        }
        var position = self.spokenIndex.flatMap { points.firstIndex(of: $0) } ?? (delta > 0 ? -1 : points.count)
        position = max(0, min(points.count - 1, position + delta))
        let index = points[position]
        self.spokenIndex = index
        self.accessibilityValue = self.spokenPoint(index, series: series, component: component)
        self.showTooltip(at: index, series: series, component: component)
    }

    private func showTooltip(at index: Int, series: GiftStatsPriceSeries, component: GiftStatsChartComponent) {
        guard let geometry = self.node.plotGeometry else {
            return
        }
        let time = series.times[index]
        let horizontal = geometry.horizontalRange
        let width = max(0.0001, horizontal.upperBound - horizontal.lowerBound)
        let fraction = max(0.0, min(1.0, (CGFloat(time) - horizontal.lowerBound) / width))
        let names = self.node.seriesNames
        let info = BaseChartController.ChartSelectionInfo(
            index: index,
            date: Date(timeIntervalSince1970: time),
            values: series.allValues.map { $0[index] },
            names: names,
            colors: names.map { _ in UIColor.white },
            fingerFraction: fraction,
            isNewPoint: true
        )
        self.selectionChanged(info)
        self.spokenHide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.selectionChanged(nil)
        }
        self.spokenHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }
}
