import Foundation
#if os(macOS)
import Cocoa
#else
import UIKit
#endif

/// Bar intro, tallest first: a bar's delay is proportional to how much shorter it is than the visible peak (up to `maxDelay`),
/// then it rises on a stiff spring over `riseDuration`. The final shape is exact after `totalDuration`.
enum GiftBarGrowth {
    static let maxDelay: TimeInterval = 0.16
    static let riseDuration: TimeInterval = 0.46
    static var totalDuration: TimeInterval {
        return GiftBarGrowth.maxDelay + GiftBarGrowth.riseDuration
    }

    // Step response of a damped spring (ratio 0.75): 1 - e^(-decay x) (cos(f x) + decay / f sin(f x)).
    private static let decay = 6.2
    private static let frequency = 5.47

    static func delay(value: CGFloat, peak: CGFloat) -> TimeInterval {
        guard peak > 0.0 else {
            return 0.0
        }
        let share = min(1.0, max(0.0, Double(value / peak)))
        return (1.0 - share) * GiftBarGrowth.maxDelay
    }

    /// Fraction of the bar's own height `elapsed` seconds after it started.
    static func height(elapsed: TimeInterval) -> CGFloat {
        guard elapsed > 0.0 else {
            return 0.0
        }
        let x = elapsed / GiftBarGrowth.riseDuration
        guard x < 1.0 else {
            return 1.0
        }
        let envelope = exp(-GiftBarGrowth.decay * x)
        return CGFloat(1.0 - envelope * (cos(GiftBarGrowth.frequency * x) + GiftBarGrowth.decay / GiftBarGrowth.frequency * sin(GiftBarGrowth.frequency * x)))
    }
}

extension BarChartRenderer {
    /// An infinite `delay` holds the bars flat without running the clock, so nothing redraws while waiting.
    func growGiftBars(peak: CGFloat, delay: TimeInterval) {
        self.giftGrowthPeak = peak
        guard delay.isFinite else {
            self.growthDelay = 0.0
            self.growthDuration = GiftBarGrowth.totalDuration
            self.growthClock.set(current: 0)
            return
        }
        self.growthDelay = delay
        self.growthDuration = delay + GiftBarGrowth.totalDuration
        self.growthClock.set(current: 0)
        self.growthClock.animate(to: 1, duration: self.growthDuration, timeFunction: .linear)
    }

    /// 0...~1.03 during growth, 1 when done.
    func giftBarGrowth(total: CGFloat) -> CGFloat {
        let clock = self.growthClock.current
        if clock >= 1 {
            return 1
        }
        let elapsed = Double(clock) * self.growthDuration - self.growthDelay - GiftBarGrowth.delay(value: total, peak: self.giftGrowthPeak)
        return GiftBarGrowth.height(elapsed: elapsed)
    }
}
