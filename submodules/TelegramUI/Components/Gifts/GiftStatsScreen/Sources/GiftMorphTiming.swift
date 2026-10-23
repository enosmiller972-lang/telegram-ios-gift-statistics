import Foundation
import UIKit
import GiftStats

// Shares of the morph time, 0 = card, 1 = stats.
public struct GiftMorphWindow {
    public var start: CGFloat
    public var length: CGFloat

    public init(start: CGFloat, length: CGFloat) {
        self.start = start
        self.length = length
    }

    public func progress(at time: CGFloat) -> CGFloat {
        return min(1.0, max(0.0, (time - self.start) / self.length))
    }
}

// position: eased progress, drives geometry. time: linear progress, drives content swaps.
// Both run 0 -> 1 towards stats and 1 -> 0 back.
public struct GiftMorphMoment {
    public var position: CGFloat
    public var time: CGFloat

    public init(position: CGFloat, time: CGFloat) {
        self.position = position
        self.time = time
    }
}

public enum GiftMorphTiming {
    public static let duration: Double = 0.65
    // Symmetric cubic bezier, so the way back is the way there reversed.
    public static let controlPoints: (Float, Float, Float, Float) = (0.4, 0.0, 0.6, 1.0)

    public static let title = GiftMorphWindow(start: 0.05, length: 0.30)
    public static let tiles = GiftMorphWindow(start: 0.10, length: 0.35)
    public static let rows = GiftMorphWindow(start: 0.22, length: 0.32)
    public static let rowStep: CGFloat = 0.07
    public static let merge = GiftMorphWindow(start: 0.70, length: 0.30)
    // Out and in overlap so the surface is never empty.
    public static let dissolveOut = GiftMorphWindow(start: 0.60, length: 0.35)
    public static let dissolveIn = GiftMorphWindow(start: 0.30, length: 0.40)
    public static let dissolveScale: CGFloat = 0.96
    // A surface whose card target has less than shrinkRatio of its area finishes its shape by shrinkDone of the way back.
    public static let shrinkRatio: CGFloat = 0.3
    public static let shrinkDone: CGFloat = 0.5
    public static let dissolveInSmall = GiftMorphWindow(start: 0.40, length: 0.20)
    public static let dissolveOutSmall = GiftMorphWindow(start: 0.55, length: 0.40)
    public static let bornContent = GiftMorphWindow(start: 0.45, length: 0.45)
    public static let fadeOut = GiftMorphWindow(start: 0.80, length: 0.20)
    public static let headings = GiftMorphWindow(start: 0.75, length: 0.25)
    // The off-screen header is born out of the topmost visible panel.
    public static let bornGift = GiftMorphWindow(start: 0.05, length: 0.40)
    public static let bornTitle = GiftMorphWindow(start: 0.15, length: 0.30)
    public static let bornScale: CGFloat = 0.35
    public static let bornGap: CGFloat = 18.0
    public static let showAll = GiftMorphWindow(start: 0.55, length: 0.30)
    public static let line = GiftMorphWindow(start: 0.30, length: 0.35)
    // Footer button fill and text change to "Buy" together (GiftMorphPair.fillsInWindow).
    public static let buy = GiftMorphWindow(start: 0.30, length: 0.40)
    public static let buyFade = GiftMorphWindow(start: 0.60, length: 0.32)
    // Shadow and rim of the real button fade in on the piece.
    public static let settle = GiftMorphWindow(start: 0.80, length: 0.20)
    public static let flatRise = GiftMorphWindow(start: 0.0, length: 0.20)
    public static let symbols = GiftMorphWindow(start: 0.0, length: 0.75)
    public static let symbolsArrive = GiftMorphWindow(start: 0.34, length: 0.46)
    public static let blocks = GiftMorphWindow(start: 0.50, length: 0.40)

    // window is measured from the start of the way back; result is eased 0...1.
    public static func back(_ window: GiftMorphWindow, at time: CGFloat) -> CGFloat {
        let t = min(1.0, max(0.0, (1.0 - time - window.start) / window.length))
        return t * t * (3.0 - 2.0 * t)
    }

    private static func bezier(_ u: CGFloat, _ p1: CGFloat, _ p2: CGFloat) -> CGFloat {
        let v = 1.0 - u
        return 3.0 * v * v * u * p1 + 3.0 * v * u * u * p2 + u * u * u
    }

    private static func solve(_ value: CGFloat, axis: (CGFloat, CGFloat)) -> CGFloat {
        var low: CGFloat = 0.0
        var high: CGFloat = 1.0
        for _ in 0 ..< 32 {
            let mid = (low + high) / 2.0
            if self.bezier(mid, axis.0, axis.1) < value {
                low = mid
            } else {
                high = mid
            }
        }
        return (low + high) / 2.0
    }

    private static var xAxis: (CGFloat, CGFloat) {
        return (CGFloat(self.controlPoints.0), CGFloat(self.controlPoints.2))
    }

    private static var yAxis: (CGFloat, CGFloat) {
        return (CGFloat(self.controlPoints.1), CGFloat(self.controlPoints.3))
    }

    static func progress(atTime time: CGFloat) -> CGFloat {
        let t = min(1.0, max(0.0, time))
        return self.bezier(self.solve(t, axis: self.xAxis), self.yAxis.0, self.yAxis.1)
    }

    static func time(atProgress progress: CGFloat) -> CGFloat {
        let s = min(1.0, max(0.0, progress))
        return self.bezier(self.solve(s, axis: self.yAxis), self.xAxis.0, self.xAxis.1)
    }

    static func slope(atTime time: CGFloat) -> CGFloat {
        let step: CGFloat = 0.01
        let low = max(0.0, time - step)
        let high = min(1.0, time + step)
        return (self.progress(atTime: high) - self.progress(atTime: low)) / (high - low)
    }
}
