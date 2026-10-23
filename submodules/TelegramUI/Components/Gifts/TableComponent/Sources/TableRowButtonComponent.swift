import Foundation
import UIKit
import Display
import ComponentFlow

/// Tap area and highlight for a table row.
final class TableRowButtonComponent: Component {
    let highlightColor: UIColor
    let maskedCorners: CACornerMask
    let cornerRadius: CGFloat
    let tag: AnyObject?
    let accessibilityLabel: String?
    let action: () -> Void

    init(highlightColor: UIColor, maskedCorners: CACornerMask, cornerRadius: CGFloat, tag: AnyObject?, accessibilityLabel: String?, action: @escaping () -> Void) {
        self.highlightColor = highlightColor
        self.maskedCorners = maskedCorners
        self.cornerRadius = cornerRadius
        self.tag = tag
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    static func ==(lhs: TableRowButtonComponent, rhs: TableRowButtonComponent) -> Bool {
        return lhs.highlightColor == rhs.highlightColor && lhs.maskedCorners == rhs.maskedCorners && lhs.cornerRadius == rhs.cornerRadius && lhs.tag === rhs.tag && lhs.accessibilityLabel == rhs.accessibilityLabel
    }

    final class View: HighlightTrackingButton, ComponentTaggedView {
        private var component: TableRowButtonComponent?
        private let highlightView = UIView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            self.highlightView.alpha = 0.0
            self.highlightView.isUserInteractionEnabled = false
            self.highlightView.layer.cornerCurve = .continuous
            self.addSubview(self.highlightView)
            self.highligthedChanged = { [weak self] highlighted in
                guard let self else {
                    return
                }
                if highlighted {
                    self.highlightView.layer.removeAnimation(forKey: "opacity")
                    self.highlightView.alpha = 1.0
                } else {
                    self.highlightView.alpha = 0.0
                    self.highlightView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3)
                }
            }
            self.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func matches(tag: Any) -> Bool {
            if let own = self.component?.tag {
                return (tag as AnyObject) === own
            }
            return false
        }

        private func hideCoveredSiblings() {
            guard let siblings = self.superview?.subviews else {
                return
            }
            for sibling in siblings where sibling !== self && self.frame.contains(CGPoint(x: sibling.frame.midX, y: sibling.frame.midY)) {
                sibling.accessibilityElementsHidden = true
            }
        }

        @objc private func pressed() {
            self.component?.action()
        }

        func update(component: TableRowButtonComponent, availableSize: CGSize) -> CGSize {
            self.component = component
            self.accessibilityLabel = component.accessibilityLabel
            self.isAccessibilityElement = component.accessibilityLabel != nil
            if component.accessibilityLabel != nil {
                // Hide row subviews from screen readers in favor of the row label.
                DispatchQueue.main.async { [weak self] in
                    self?.hideCoveredSiblings()
                }
            }
            self.highlightView.backgroundColor = component.highlightColor
            self.highlightView.frame = CGRect(origin: .zero, size: availableSize)
            self.highlightView.layer.cornerRadius = component.cornerRadius
            self.highlightView.layer.maskedCorners = component.maskedCorners
            return availableSize
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize)
    }
}
