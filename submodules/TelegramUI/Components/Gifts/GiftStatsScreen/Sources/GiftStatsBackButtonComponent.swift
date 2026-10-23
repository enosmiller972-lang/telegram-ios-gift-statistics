import Foundation
import UIKit
import Display
import ComponentFlow
import BundleIconComponent

final class GiftStatsBackButtonComponent: Component {
    static let side: CGFloat = 44.0

    let icon: String
    let tile: GiftStatsTileSurface
    let label: String
    let action: () -> Void

    init(icon: String, tile: GiftStatsTileSurface, label: String, action: @escaping () -> Void) {
        self.icon = icon
        self.tile = tile
        self.label = label
        self.action = action
    }

    static func ==(lhs: GiftStatsBackButtonComponent, rhs: GiftStatsBackButtonComponent) -> Bool {
        return lhs.icon == rhs.icon && lhs.tile == rhs.tile && lhs.label == rhs.label
    }

    final class View: GiftFlatTonalView {
        private let icon = ComponentView<Empty>()

        func update(component: GiftStatsBackButtonComponent, transition: ComponentTransition) -> CGSize {
            let size = CGSize(width: GiftStatsBackButtonComponent.side, height: GiftStatsBackButtonComponent.side)
            self.action = component.action
            self.label = component.label
            self.bounds = CGRect(origin: .zero, size: size)
            self.update(tile: component.tile, shape: .capsule)
            let iconSize = self.icon.update(
                transition: transition,
                component: AnyComponent(BundleIconComponent(name: component.icon, tintColor: .white)),
                environment: {},
                containerSize: size
            )
            if let iconView = self.icon.view {
                if iconView.superview == nil {
                    iconView.isUserInteractionEnabled = false
                    self.addSubview(iconView)
                }
                iconView.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - iconSize.width) / 2.0), y: floorToScreenPixels((size.height - iconSize.height) / 2.0)), size: iconSize)
            }
            return size
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, transition: transition)
    }
}
