import Foundation
import UIKit
import GiftStats

enum GiftStatsInitialRange {
    static let days = 90

    /// The last `days` of the data; `0...1` is everything.
    static func fraction(series: GiftStatsPriceSeries) -> ClosedRange<CGFloat> {
        guard let first = series.times.first, let last = series.times.last, last > first else {
            return 0.0 ... 1.0
        }
        let lower = max(0.0, 1.0 - Double(self.days) * 86400.0 / (last - first))
        return CGFloat(lower) ... 1.0
    }
}
