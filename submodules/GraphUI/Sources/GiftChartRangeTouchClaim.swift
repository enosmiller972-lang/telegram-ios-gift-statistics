import UIKit

/// Once a slider drag turns horizontal, disables ancestor pan gestures (card scroll, gift pager, sheet) until touch up.
final class GiftChartRangeTouchClaim {
    static let decisionDistance: CGFloat = 8.0

    enum Direction {
        case undecided
        case horizontal
        case vertical
    }

    private var held: [(recognizer: UIPanGestureRecognizer, wasEnabled: Bool)] = []

    var isHolding: Bool {
        return !self.held.isEmpty
    }

    static func direction(dx: CGFloat, dy: CGFloat) -> Direction {
        if hypot(dx, dy) < self.decisionDistance {
            return .undecided
        }
        return abs(dx) >= abs(dy) ? .horizontal : .vertical
    }

    func hold(above view: UIView) {
        guard self.held.isEmpty else {
            return
        }
        var current = view.superview
        while let parent = current {
            for recognizer in parent.gestureRecognizers ?? [] {
                if let pan = recognizer as? UIPanGestureRecognizer, pan.isEnabled {
                    self.held.append((pan, true))
                    pan.isEnabled = false
                }
            }
            current = parent.superview
        }
    }

    func release() {
        for item in self.held {
            item.recognizer.isEnabled = item.wasEnabled
        }
        self.held.removeAll()
    }

    deinit {
        self.release()
    }
}
