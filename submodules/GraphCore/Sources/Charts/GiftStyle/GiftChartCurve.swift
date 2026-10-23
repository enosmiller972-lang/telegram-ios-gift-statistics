import Foundation
#if os(macOS)
import Cocoa
#else
import UIKit
#endif

/// `.off` is the stock look; `.main` and `.preview` are the gift plot and its range slider chart (`BaseChartController.giftStyle`).
enum GiftChartRole {
    case off
    case main
    case preview
}

enum GiftChartCurve {
    /// Averages points into `bucketWidth` buckets to avoid jitter; the first and last points are kept as is.
    static func downsample(_ points: [CGPoint], bucketWidth: CGFloat) -> [CGPoint] {
        guard points.count > 3, let first = points.first, let last = points.last else {
            return points
        }
        var result: [CGPoint] = [first]
        var sum = CGPoint.zero
        var count: CGFloat = 0.0
        var bucket = floor((points[1].x - first.x) / bucketWidth)
        func flush() {
            guard count > 0.0 else {
                return
            }
            let point = CGPoint(x: sum.x / count, y: sum.y / count)
            if let previous = result.last, point.x - previous.x >= bucketWidth * 0.5, last.x - point.x >= bucketWidth * 0.5 {
                result.append(point)
            }
            sum = .zero
            count = 0.0
        }
        for index in 1 ..< points.count - 1 {
            let point = points[index]
            let current = floor((point.x - first.x) / bucketWidth)
            if current != bucket {
                flush()
                bucket = current
            }
            sum.x += point.x
            sum.y += point.y
            count += 1.0
        }
        flush()
        result.append(last)
        return result
    }

    /// Smoothed path plus the same curve as y(x). Anything placed on the line must use `y(atX:)`, not the raw points.
    struct Fit {
        let points: [CGPoint]
        private let slopes: [CGFloat]

        init(_ points: [CGPoint]) {
            self.points = points
            let count = points.count
            guard count >= 2 else {
                self.slopes = [CGFloat](repeating: 0.0, count: count)
                return
            }
            var h = [CGFloat](repeating: 0.0, count: count - 1)
            var d = [CGFloat](repeating: 0.0, count: count - 1)
            for k in 0 ..< count - 1 {
                h[k] = max(0.0001, points[k + 1].x - points[k].x)
                d[k] = (points[k + 1].y - points[k].y) / h[k]
            }
            var m = [CGFloat](repeating: 0.0, count: count)
            m[0] = d[0]
            m[count - 1] = d[count - 2]
            if count > 2 {
                for k in 1 ..< count - 1 {
                    if d[k - 1] * d[k] <= 0.0 {
                        m[k] = 0.0
                    } else {
                        let w1 = 2.0 * h[k] + h[k - 1]
                        let w2 = h[k] + 2.0 * h[k - 1]
                        m[k] = (w1 + w2) / (w1 / d[k - 1] + w2 / d[k])
                    }
                }
            }
            self.slopes = m
        }

        var path: CGPath {
            let path = CGMutablePath()
            guard let first = self.points.first else {
                return path
            }
            path.move(to: first)
            let count = self.points.count
            if count == 2 {
                path.addLine(to: self.points[1])
                return path
            }
            if count < 2 {
                return path
            }
            for k in 0 ..< count - 1 {
                let p0 = self.points[k]
                let p1 = self.points[k + 1]
                let step = max(0.0001, p1.x - p0.x) / 3.0
                path.addCurve(
                    to: p1,
                    control1: CGPoint(x: p0.x + step, y: p0.y + self.slopes[k] * step),
                    control2: CGPoint(x: p1.x - step, y: p1.y - self.slopes[k + 1] * step)
                )
            }
            return path
        }

        /// Nil outside the points. Control points sit at thirds of each segment, so x is linear in t and this Hermite is exact.
        func y(atX x: CGFloat) -> CGFloat? {
            guard let first = self.points.first, let last = self.points.last, x >= first.x, x <= last.x else {
                return nil
            }
            if self.points.count == 1 {
                return first.y
            }
            var low = 0
            var high = self.points.count - 1
            while high - low > 1 {
                let middle = (low + high) / 2
                if self.points[middle].x <= x {
                    low = middle
                } else {
                    high = middle
                }
            }
            let p0 = self.points[low]
            let p1 = self.points[high]
            let h = max(0.0001, p1.x - p0.x)
            let t = min(1.0, max(0.0, (x - p0.x) / h))
            let t2 = t * t
            let t3 = t2 * t
            return (2.0 * t3 - 3.0 * t2 + 1.0) * p0.y + (t3 - 2.0 * t2 + t) * h * self.slopes[low] + (-2.0 * t3 + 3.0 * t2) * p1.y + (t3 - t2) * h * self.slopes[high]
        }
    }
}
