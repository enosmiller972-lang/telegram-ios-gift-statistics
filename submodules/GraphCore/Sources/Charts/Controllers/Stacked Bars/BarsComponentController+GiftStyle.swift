import Foundation
#if os(macOS)
import Cocoa
#else
import UIKit
#endif

/// Gift-style bars group days into weeks or months; vertical range and selection follow the drawn buckets.
extension BarsComponentController {
    var isGiftStyle: Bool {
        return self.mainBarsRenderer.giftRole != .off
    }

    func barsForVerticalRange(_ renderer: BarChartRenderer, range: ClosedRange<CGFloat>) -> BarChartRenderer.BarsData {
        guard renderer.giftRole != .off, !renderer.bars.locations.isEmpty else {
            return self.visibleBars
        }
        let data = renderer.giftLevel(forVisibleRange: range).data
        let visibleComponents: [BarChartRenderer.BarsData.Component] = chartVisibility.enumerated().compactMap { args in
            args.element && args.offset < data.components.count ? data.components[args.offset] : nil
        }
        return BarChartRenderer.BarsData(barWidth: data.barWidth, locations: data.locations, components: visibleComponents)
    }

    func bucketedSelection(_ info: BaseChartController.ChartSelectionInfo) -> BaseChartController.ChartSelectionInfo {
        guard self.isGiftStyle, !self.mainBarsRenderer.bars.locations.isEmpty else {
            return info
        }
        let level = self.mainBarsRenderer.giftLevel(forVisibleRange: self.mainBarsRenderer.horizontalRange.end)
        guard info.index < level.rawToBucket.count else {
            return info
        }
        let bucket = level.rawToBucket[info.index]
        var result = info
        result.isNewPoint = self.lastSelectedBucket != bucket
        self.lastSelectedBucket = bucket
        if level.size > 1 {
            let dates = self.chartsCollection.axisValues
            result.index = level.firstRaw[bucket]
            result.date = dates[level.firstRaw[bucket]]
            result.endDate = dates[level.lastRaw[bucket]]
            result.values = level.data.components.map { Double($0.values[bucket]) }
        }
        return result
    }
}
