import Foundation
import UIKit
import Display
import ComponentFlow
import ButtonComponent

/// Displays the animated title for the Buy button.
final class GiftStatsBuyContentComponent: Component {
    private static let titleFont = Font.semibold(17.0)

    let title: GiftStatsNumberLineView.Content
    let color: UIColor

    init(title: GiftStatsNumberLineView.Content, color: UIColor) {
        self.title = title
        self.color = color
    }

    static func ==(lhs: GiftStatsBuyContentComponent, rhs: GiftStatsBuyContentComponent) -> Bool {
        return lhs.title == rhs.title && lhs.color == rhs.color
    }

    final class View: UIView {
        private let titleLine = GiftStatsNumberLineView()
        private var hasContent = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            self.isUserInteractionEnabled = false
            self.addSubview(self.titleLine)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(component: GiftStatsBuyContentComponent, availableSize: CGSize) -> CGSize {
            let titleSize = GiftStatsNumberLineView.size(content: component.title, font: GiftStatsBuyContentComponent.titleFont)
            let size = CGSize(width: max(availableSize.width, titleSize.width), height: titleSize.height)
            let titleFrame = CGRect(origin: CGPoint(x: floor((size.width - titleSize.width) / 2.0), y: 0.0), size: titleSize)
            let isAnimated = self.hasContent
            self.hasContent = true
            GiftStatsNumericTextView.move(animated: isAnimated) {
                self.titleLine.bounds = CGRect(origin: .zero, size: titleSize)
                self.titleLine.center = CGPoint(x: titleFrame.midX, y: titleFrame.midY)
            }
            self.titleLine.update(content: component.title, font: GiftStatsBuyContentComponent.titleFont, color: component.color, animated: true)
            return size
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize)
    }
}

/// The collection store button pinned to the bottom of the statistics screen.
final class GiftStatsStoreButtonComponent: Component {
    static let height: CGFloat = 52.0
    static let sideInset: CGFloat = 30.0
    private static let minimumBottomInset: CGFloat = 30.0

    static func bottomInset(device: CGFloat) -> CGFloat {
        return max(device, GiftStatsStoreButtonComponent.minimumBottomInset)
    }

    let title: GiftStatsNumberLineView.Content
    let label: String
    /// The colours of the check marks of the theme, as the Craft Gift screen takes them: the fill of the button and the colour of its text.
    let fill: UIColor
    let foreground: UIColor
    let action: () -> Void

    init(title: GiftStatsNumberLineView.Content, label: String, fill: UIColor, foreground: UIColor, action: @escaping () -> Void) {
        self.title = title
        self.label = label
        self.fill = fill
        self.foreground = foreground
        self.action = action
    }

    static func ==(lhs: GiftStatsStoreButtonComponent, rhs: GiftStatsStoreButtonComponent) -> Bool {
        return lhs.title == rhs.title && lhs.label == rhs.label && lhs.fill == rhs.fill && lhs.foreground == rhs.foreground
    }

    final class View: UIView {
        private let button = ComponentView<Empty>()
        private var component: GiftStatsStoreButtonComponent?

        override init(frame: CGRect) {
            super.init(frame: frame)
            self.isAccessibilityElement = true
            self.accessibilityTraits = .button
        }

        override func accessibilityActivate() -> Bool {
            guard let component = self.component else {
                return false
            }
            component.action()
            return true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        var fill: UIColor? {
            return self.component?.fill
        }

        var contentView: UIView? {
            return self.button.view.flatMap { View.findContent(in: $0) }
        }

        private static func findContent(in view: UIView) -> UIView? {
            if view is GiftStatsBuyContentComponent.View {
                return view
            }
            for subview in view.subviews {
                if let found = self.findContent(in: subview) {
                    return found
                }
            }
            return nil
        }

        func accents() -> [GiftMorphAccent] {
            guard let button = self.button.view else {
                return []
            }
            var accents: [GiftMorphAccent] = []
            for subview in button.subviews {
                let images = subview is UIImageView ? [subview] : subview.subviews.filter { $0 is UIImageView }
                for case let view as UIImageView in images {
                    guard let image = view.image else {
                        continue
                    }
                    let outset = max(0.0, (view.bounds.width - button.bounds.width) / 2.0)
                    accents.append(GiftMorphAccent(image: image, outset: outset, alpha: view.alpha, compositingFilter: view.layer.compositingFilter, isUnder: outset > 0.5))
                }
            }
            return accents
        }

        private var pictureCache: (key: String, image: UIImage)?

        func contentPicture() -> UIView? {
            guard let content = self.contentView, content.bounds.width > 0.0 else {
                return nil
            }
            let key = self.pictureKey(size: content.bounds.size)
            if let cache = self.pictureCache, cache.key == key {
                let picture = UIImageView(image: cache.image)
                picture.frame = CGRect(origin: .zero, size: content.bounds.size)
                return picture
            }
            return GiftMorphCapture.picture(of: content)
        }

        private func pictureKey(size: CGSize) -> String {
            guard let component = self.component else {
                return ""
            }
            return "\(component.title)|\(component.foreground.hashValue)|\(size.width)x\(size.height)"
        }

        private func prepareContentPicture() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let content = self.contentView, content.bounds.width > 0.0 else {
                    return
                }
                let key = self.pictureKey(size: content.bounds.size)
                if self.pictureCache?.key == key {
                    return
                }
                if let picture = GiftMorphCapture.picture(of: content) as? UIImageView, let image = picture.image {
                    self.pictureCache = (key, image)
                }
            }
        }

        func update(component: GiftStatsStoreButtonComponent, availableSize: CGSize) -> CGSize {
            self.component = component
            self.accessibilityLabel = component.label
            let size = CGSize(width: availableSize.width, height: GiftStatsStoreButtonComponent.height)
            let buttonSize = self.button.update(
                transition: .immediate,
                component: AnyComponent(ButtonComponent(
                    background: ButtonComponent.Background(
                        style: GiftStatsEnvironment.reduceTransparency ? .legacy : .glass,
                        color: component.fill,
                        foreground: component.foreground,
                        pressedColor: component.fill.withMultipliedAlpha(0.9)
                    ),
                    content: AnyComponentWithIdentity(id: AnyHashable("buy"), component: AnyComponent(GiftStatsBuyContentComponent(title: component.title, color: component.foreground))),
                    action: { [weak self] in
                        self?.component?.action()
                    }
                )),
                environment: {},
                containerSize: size
            )
            if let buttonView = self.button.view {
                if buttonView.superview == nil {
                    self.addSubview(buttonView)
                }
                buttonView.frame = CGRect(origin: .zero, size: buttonSize)
            }
            self.prepareContentPicture()
            return buttonSize
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize)
    }
}
