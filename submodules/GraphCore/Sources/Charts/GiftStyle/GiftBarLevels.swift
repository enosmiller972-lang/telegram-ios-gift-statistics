import Foundation
#if os(macOS)
import Cocoa
#else
import UIKit
#endif

/// Groups bars into day/week/month buckets so at most `maxVisible` are visible. Buckets are counted back from the newest bar
/// so they don't shift while the range slides.
struct GiftChartBarLevels {
    struct Level {
        /// Raw bars per bucket.
        let size: Int
        /// Located at the newest raw bar, `size` raw widths wide, values are sums.
        let data: BarChartRenderer.BarsData
        let rawToBucket: [Int]
        let firstRaw: [Int]
        let lastRaw: [Int]
    }

    static let sizes = [1, 7, 30, 90, 365]
    static let maxVisible = 40

    let levels: [Level]
    let rawWidth: CGFloat

    init(bars: BarChartRenderer.BarsData) {
        self.rawWidth = max(0.0001, bars.barWidth)
        let count = bars.locations.count
        var levels: [Level] = []
        for size in GiftChartBarLevels.sizes {
            if size == 1 || count == 0 {
                levels.append(Level(size: 1, data: bars, rawToBucket: Array(0 ..< count), firstRaw: Array(0 ..< count), lastRaw: Array(0 ..< count)))
                if count == 0 {
                    break
                }
                continue
            }
            let bucketCount = (count + size - 1) / size
            var locations: [CGFloat] = []
            var firstRaw: [Int] = []
            var lastRaw: [Int] = []
            var rawToBucket = [Int](repeating: 0, count: count)
            var components = bars.components.map { BarChartRenderer.BarsData.Component(color: $0.color, values: []) }
            for bucket in 0 ..< bucketCount {
                let last = count - (bucketCount - 1 - bucket) * size - 1
                let first = max(0, last - size + 1)
                locations.append(bars.locations[last])
                firstRaw.append(first)
                lastRaw.append(last)
                for index in first ... last {
                    rawToBucket[index] = bucket
                }
                for (componentIndex, component) in bars.components.enumerated() {
                    var sum: CGFloat = 0.0
                    for index in first ... last where index < component.values.count {
                        sum += component.values[index]
                    }
                    components[componentIndex].values.append(sum)
                }
            }
            levels.append(Level(
                size: size,
                data: BarChartRenderer.BarsData(barWidth: bars.barWidth * CGFloat(size), locations: locations, components: components),
                rawToBucket: rawToBucket,
                firstRaw: firstRaw,
                lastRaw: lastRaw
            ))
        }
        self.levels = levels
    }

    /// Smallest bucket size that keeps at most `maxVisible` buckets in the range.
    func level(forVisibleRange range: ClosedRange<CGFloat>, maxVisible: Int = GiftChartBarLevels.maxVisible) -> Level {
        let visibleBars = Int(ceil((range.upperBound - range.lowerBound) / self.rawWidth))
        for level in self.levels {
            if (visibleBars + level.size - 1) / level.size <= maxVisible {
                return level
            }
        }
        return self.levels[self.levels.count - 1]
    }
}
