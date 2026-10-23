import Foundation
import UIKit

// Drawn above all morph pieces.
public protocol GiftMorphExtra: AnyObject {
    func install(in overlay: UIView)
    func apply(_ moment: GiftMorphMoment)
    func land(toStats: Bool)
}

public final class GiftStatsHeadingReveal: GiftMorphExtra {
    private let lines: [UIView]

    public init(lines: [UIView]) {
        self.lines = lines
    }

    public func install(in overlay: UIView) {
    }

    public func apply(_ moment: GiftMorphMoment) {
        let t = min(1.0, max(0.0, GiftMorphTiming.valueHeading.progress(at: moment.time)))
        let shown = t * t * (3.0 - 2.0 * t)
        for line in self.lines {
            line.alpha = shown
            line.transform = CGAffineTransform(translationX: 0.0, y: (1.0 - shown) * GiftMorphTiming.valueHeadingRise)
        }
    }

    public func land(toStats: Bool) {
        for line in self.lines {
            line.transform = .identity
            line.alpha = toStats ? 1.0 : 0.0
        }
    }
}
