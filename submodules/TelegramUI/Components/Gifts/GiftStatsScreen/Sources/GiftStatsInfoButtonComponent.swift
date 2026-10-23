import Foundation
import UIKit
import Display
import ComponentFlow
import MultilineTextComponent

final class GiftStatsInfoButtonComponent: Component {
    let text: String
    let color: UIColor
    let action: (UIView) -> Void

    init(text: String, color: UIColor, action: @escaping (UIView) -> Void) {
        self.text = text
        self.color = color
        self.action = action
    }

    static func ==(lhs: GiftStatsInfoButtonComponent, rhs: GiftStatsInfoButtonComponent) -> Bool {
        return lhs.text == rhs.text && lhs.color == rhs.color
    }

    final class View: UIView {
        private var component: GiftStatsInfoButtonComponent?
        private let backgroundLayer = SimpleLayer()
        private let title = ComponentView<Empty>()

        override init(frame: CGRect) {
            super.init(frame: frame)
            self.layer.addSublayer(self.backgroundLayer)
            self.backgroundLayer.masksToBounds = true
            self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapped)))
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc private func tapped() {
            self.component?.action(self)
        }

        func update(component: GiftStatsInfoButtonComponent, availableSize: CGSize, transition: ComponentTransition) -> CGSize {
            self.component = component
            let titleSize = self.title.update(
                transition: transition,
                component: AnyComponent(MultilineTextComponent(text: .plain(NSAttributedString(string: component.text, font: Font.regular(11.0), textColor: component.color)))),
                environment: {},
                containerSize: availableSize
            )
            let size = CGSize(width: titleSize.width + 12.0, height: 18.0)
            if let titleView = self.title.view {
                if titleView.superview == nil {
                    self.addSubview(titleView)
                }
                titleView.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - titleSize.width) / 2.0), y: floorToScreenPixels((size.height - titleSize.height) / 2.0)), size: titleSize)
            }
            self.backgroundLayer.backgroundColor = component.color.withAlphaComponent(0.1).cgColor
            self.backgroundLayer.frame = CGRect(origin: .zero, size: size)
            self.backgroundLayer.cornerRadius = size.height / 2.0
            return size
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, transition: transition)
    }
}
