import Foundation
import UIKit
import Display
import ComponentFlow
import GiftStats

/// The sales log's nested scroll view. Scrolling past its edges hands off to the card's scroll view when the card can move;
/// otherwise the list rubber-bands, so a pull-down inside the list never dismisses the card.
final class GiftStatsSalesListView: UIView, UIScrollViewDelegate {
    private final class HandoverScrollView: UIScrollView {
        var outer: UIScrollView? {
            var view = self.superview
            while let current = view {
                if let scroll = current as? UIScrollView {
                    return scroll
                }
                view = current.superview
            }
            return nil
        }

        /// A drag starting at an edge and pushing past it goes to the card if the card can move that way.
        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === self.panGestureRecognizer, let outer = self.outer {
                let velocity = self.panGestureRecognizer.velocity(in: self)
                if abs(velocity.y) > abs(velocity.x) {
                    let maximum = max(0.0, self.contentSize.height - self.bounds.height)
                    let outerMaximum = max(0.0, outer.contentSize.height - outer.bounds.height)
                    if velocity.y > 0.0 && self.contentOffset.y <= 0.5 && outer.contentOffset.y > 0.5 {
                        return false
                    }
                    if velocity.y < 0.0 && self.contentOffset.y >= maximum - 0.5 && outer.contentOffset.y < outerMaximum - 0.5 {
                        return false
                    }
                }
            }
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
    }

    private static let fadeHeight: CGFloat = 22.0
    /// Alpha at the top and bottom of the last row of the closed list.
    private static let closedFadeTop: CGFloat = 0.75
    private static let closedFadeBottom: CGFloat = 0.05

    private let scroll = HandoverScrollView()
    private let fade = CAGradientLayer()
    /// Opaque above the last row, then linear from `closedFadeTop` to `closedFadeBottom`.
    static func closedFadeAlpha(y: CGFloat, height: CGFloat) -> CGFloat {
        let rowHeight = min(height, GiftStatsSalesRowView.height)
        let start = height - rowHeight
        guard y > start else {
            return 1.0
        }
        let t = min(1.0, (y - start) / max(1.0, rowHeight))
        return self.closedFadeTop + (self.closedFadeBottom - self.closedFadeTop) * t
    }

    var scrolled: (() -> Void)?
    var nearEnd: (() -> Void)?
    private var closedFade = false
    private var isOpen = false
    private var isHandingOver = false
    private var lastOffset: CGFloat = 0.0
    /// Upward scrolls go to the card first until "Show Less" is visible: with paging the list may never reach its end.
    var cardShortfall: (() -> CGFloat)?

    var contentView: UIView {
        return self.scroll
    }

    var contentOffset: CGFloat {
        return self.scroll.contentOffset.y
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.scroll.delegate = self
        self.scroll.showsVerticalScrollIndicator = false
        self.scroll.showsHorizontalScrollIndicator = false
        self.scroll.alwaysBounceVertical = true
        self.scroll.scrollsToTop = false
        self.scroll.contentInsetAdjustmentBehavior = .never
        self.scroll.delaysContentTouches = false
        self.scroll.canCancelContentTouches = true
        self.addSubview(self.scroll)
        self.fade.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.fade.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.layer.mask = self.fade
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(height: CGFloat, width: CGFloat, contentHeight: CGFloat, isOpen: Bool, closedFade: Bool, transition: ComponentTransition) {
        var fadeDuration: Double = 0.0
        if case .none = transition.animation {
        } else if (self.closedFade != closedFade || self.isOpen != isOpen) && !GiftStatsEnvironment.reduceMotion {
            fadeDuration = 0.4
        }
        self.closedFade = closedFade
        self.isOpen = isOpen
        let size = CGSize(width: width, height: height)
        transition.setFrame(view: self.scroll, frame: CGRect(origin: .zero, size: size))
        transition.setFrame(layer: self.fade, frame: CGRect(origin: .zero, size: size))
        let contentSize = CGSize(width: width, height: contentHeight)
        if self.scroll.contentSize != contentSize {
            self.scroll.contentSize = contentSize
        }
        self.scroll.isScrollEnabled = isOpen && contentHeight > height + UIScreenPixel
        if !isOpen, self.scroll.contentOffset.y != 0.0 {
            self.scroll.setContentOffset(.zero, animated: !GiftStatsEnvironment.reduceMotion)
        }
        self.updateFade(duration: fadeDuration)
    }

    /// Edge fades grow with the content hidden past each edge.
    private func updateFade(duration: Double = 0.0) {
        let height = max(1.0, self.scroll.bounds.height)
        let maximum = max(0.0, self.scroll.contentSize.height - height)
        let offset = self.scroll.contentOffset.y
        let top = min(1.0, max(0.0, offset / GiftStatsSalesListView.fadeHeight))
        let bottom = min(1.0, max(0.0, (maximum - offset) / GiftStatsSalesListView.fadeHeight))
        if self.closedFade && !self.isOpen {
            // The alpha step sits on the row separator, where it is not visible.
            let start = max(0.0, 1.0 - min(1.0, GiftStatsSalesRowView.height / height))
            let steps = 4
            var colors: [CGColor] = [UIColor.black.cgColor, UIColor.black.cgColor]
            var locations: [NSNumber] = [0.0, NSNumber(value: Double(start))]
            for step in 0 ... steps {
                let t = CGFloat(step) / CGFloat(steps)
                let location = start + (1.0 - start) * t
                colors.append(UIColor(white: 0.0, alpha: GiftStatsSalesListView.closedFadeAlpha(y: max(location * height, start * height + 0.01), height: height)).cgColor)
                locations.append(NSNumber(value: Double(location)))
            }
            self.applyMask(colors: colors, locations: locations, duration: duration)
            return
        }
        let fraction = min(0.45, GiftStatsSalesListView.fadeHeight / height)
        self.applyMask(colors: [
            UIColor(white: 0.0, alpha: 1.0 - top).cgColor,
            UIColor.black.cgColor,
            UIColor.black.cgColor,
            UIColor(white: 0.0, alpha: 1.0 - bottom).cgColor
        ], locations: [0.0, NSNumber(value: Double(fraction)), NSNumber(value: Double(1.0 - fraction)), 1.0], duration: duration)
    }

    /// The open and closed masks differ in stop count, so the shorter list is padded with its last stop before animating.
    private func applyMask(colors: [CGColor], locations: [NSNumber], duration: Double) {
        // Scrolling updates the mask every frame without a duration, so skip reading the old one then.
        var oldColors: [CGColor]?
        var oldLocations: [NSNumber]?
        if duration > 0.0 {
            let source = self.fade.animation(forKey: "gift.stats.mask") != nil ? self.fade.presentation() : nil
            oldColors = source?.colors as? [CGColor] ?? self.fade.colors as? [CGColor]
            oldLocations = source?.locations ?? self.fade.locations
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.fade.removeAnimation(forKey: "gift.stats.mask")
        self.fade.colors = colors
        self.fade.locations = locations
        CATransaction.commit()
        guard duration > 0.0, let oldColors, let oldLocations, !oldColors.isEmpty, oldColors.count == oldLocations.count else {
            return
        }
        let count = max(colors.count, oldColors.count)
        func padded<T>(_ list: [T]) -> [T] {
            return list + Array(repeating: list[list.count - 1], count: count - list.count)
        }
        let colorsAnimation = CABasicAnimation(keyPath: "colors")
        colorsAnimation.fromValue = padded(oldColors)
        colorsAnimation.toValue = padded(colors)
        let locationsAnimation = CABasicAnimation(keyPath: "locations")
        locationsAnimation.fromValue = padded(oldLocations)
        locationsAnimation.toValue = padded(locations)
        let group = CAAnimationGroup()
        group.animations = [colorsAnimation, locationsAnimation]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        self.fade.add(group, forKey: "gift.stats.mask")
    }

    /// Moves the overscroll of a drag or deceleration to the card, as far as the card can scroll.
    private func handOver() {
        guard self.isOpen, !self.isHandingOver, self.scroll.isTracking || self.scroll.isDecelerating, let outer = self.scroll.outer else {
            return
        }
        let offset = self.scroll.contentOffset.y
        let delta = offset - self.lastOffset
        let maximum = max(0.0, self.scroll.contentSize.height - self.scroll.bounds.height)
        let outerMaximum = max(0.0, outer.contentSize.height - outer.bounds.height)
        var move: CGFloat = 0.0
        if delta > 0.0, offset > 0.0, let shortfall = self.cardShortfall?(), shortfall > 0.5 {
            move = min(delta, shortfall, outerMaximum - outer.contentOffset.y)
        } else if offset > maximum {
            move = min(offset - maximum, outerMaximum - outer.contentOffset.y)
        } else if offset < 0.0 {
            move = -min(-offset, outer.contentOffset.y)
        }
        guard abs(move) > 0.01 else {
            return
        }
        self.isHandingOver = true
        outer.contentOffset = CGPoint(x: outer.contentOffset.x, y: outer.contentOffset.y + move)
        self.scroll.contentOffset = CGPoint(x: 0.0, y: offset - move)
        self.isHandingOver = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.handOver()
        self.lastOffset = scrollView.contentOffset.y
        self.updateFade()
        self.scrolled?()
        let remaining = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.bounds.height
        if remaining < GiftStatsSalesRowView.height * 3.0 {
            self.nearEnd?()
        }
    }
}
