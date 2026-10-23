import Foundation
import UIKit
import Display
import ComponentFlow
import BundleIconComponent
import LottieComponent
import LottieSettings
import GiftStatsScreen

/// Corner buttons of a collectible card, styled with `GiftStatsTileStyle`. Leading items go to the left edge, the rest to the right.
final class GiftCardCornerButtonsComponent: Component {
    struct Item: Equatable {
        enum Content: Equatable {
            case icon(String)
            case animation(String)
        }

        let id: AnyHashable
        let content: Content
        let label: String
        let action: () -> Void

        static func ==(lhs: Item, rhs: Item) -> Bool {
            return lhs.id == rhs.id && lhs.content == rhs.content && lhs.label == rhs.label
        }
    }

    static let side: CGFloat = 44.0
    static let spacing: CGFloat = 8.0

    let leading: [Item]
    let trailing: [Item]
    let tile: GiftStatsTileSurface
    let tag: AnyObject?

    init(leading: [Item], trailing: [Item], tile: GiftStatsTileSurface, tag: AnyObject? = nil) {
        self.leading = leading
        self.trailing = trailing
        self.tile = tile
        self.tag = tag
    }

    static func ==(lhs: GiftCardCornerButtonsComponent, rhs: GiftCardCornerButtonsComponent) -> Bool {
        return lhs.leading == rhs.leading && lhs.trailing == rhs.trailing && lhs.tile == rhs.tile && lhs.tag === rhs.tag
    }

    final class Button {
        let flat = GiftFlatTonalView()
        private let icon = ComponentView<Empty>()
        private let playOnce = ActionSlot<Void>()

        func update(item: Item, tile: GiftStatsTileSurface) {
            let size = CGSize(width: GiftCardCornerButtonsComponent.side, height: GiftCardCornerButtonsComponent.side)
            self.flat.bounds = CGRect(origin: .zero, size: size)
            self.flat.update(tile: tile, shape: .capsule)
            self.flat.label = item.label
            let playOnce = self.playOnce
            let content: AnyComponent<Empty>
            var isAnimated = false
            switch item.content {
            case let .icon(name):
                content = AnyComponent(BundleIconComponent(name: name, tintColor: .white))
            case let .animation(name):
                isAnimated = true
                content = AnyComponent(LottieComponent(
                    content: LottieComponent.AppBundleContent(name: name),
                    color: .white,
                    size: CGSize(width: 32.0, height: 32.0),
                    playOnce: playOnce,
                    lottieSettings: .noAccountFallback
                ))
            }
            self.flat.action = {
                item.action()
                if isAnimated {
                    playOnce.invoke(Void())
                }
            }
            let iconSize = self.icon.update(transition: .immediate, component: content, environment: {}, containerSize: size)
            if let iconView = self.icon.view {
                if iconView.superview == nil {
                    iconView.isUserInteractionEnabled = false
                    self.flat.addSubview(iconView)
                }
                iconView.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - iconSize.width) / 2.0), y: floorToScreenPixels((size.height - iconSize.height) / 2.0)), size: iconSize)
            }
        }
    }

    final class View: UIView, ComponentTaggedView {
        private var component: GiftCardCornerButtonsComponent?
        private var buttons: [AnyHashable: Button] = [:]

        func matches(tag: Any) -> Bool {
            if let componentTag = self.component?.tag {
                return componentTag === (tag as AnyObject)
            }
            return false
        }

        /// Used as the context menu source.
        func button(id: AnyHashable) -> UIView? {
            return self.buttons[id]?.flat
        }

        func update(component: GiftCardCornerButtonsComponent, availableSize: CGSize, transition: ComponentTransition) -> CGSize {
            self.component = component
            let side = GiftCardCornerButtonsComponent.side
            let size = CGSize(width: availableSize.width, height: side)
            var validIds = Set<AnyHashable>()
            func place(_ item: Item, x: CGFloat) {
                validIds.insert(item.id)
                let button: Button
                if let current = self.buttons[item.id] {
                    button = current
                } else {
                    button = Button()
                    button.flat.frame = CGRect(origin: .zero, size: CGSize(width: side, height: side))
                    self.buttons[item.id] = button
                    self.addSubview(button.flat)
                }
                button.update(item: item, tile: component.tile)
                transition.setFrame(view: button.flat, frame: CGRect(origin: CGPoint(x: x, y: 0.0), size: CGSize(width: side, height: side)))
            }
            var x: CGFloat = 0.0
            for item in component.leading {
                place(item, x: x)
                x += side + GiftCardCornerButtonsComponent.spacing
            }
            x = size.width
            for item in component.trailing.reversed() {
                x -= side
                place(item, x: x)
                x -= GiftCardCornerButtonsComponent.spacing
            }
            for (id, button) in self.buttons where !validIds.contains(id) {
                button.flat.removeFromSuperview()
                self.buttons.removeValue(forKey: id)
            }
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
