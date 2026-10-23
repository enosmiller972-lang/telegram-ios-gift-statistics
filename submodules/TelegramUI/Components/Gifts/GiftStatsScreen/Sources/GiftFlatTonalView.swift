import Foundation
import UIKit
import Display
import ComponentFlow
import GiftStats

// border is not drawn directly: its alpha relative to GiftTonalPalette.rim sets the strength of the GiftRimView.
public struct GiftFlat: Equatable {
    public var rimStrength: CGFloat {
        guard let border = self.border else {
            return 0.0
        }
        var alpha: CGFloat = 0.0
        border.getWhite(nil, alpha: &alpha)
        return min(1.0, alpha / GiftTonalPalette.rim.cgColor.alpha)
    }

    public var fill: UIColor
    public var border: UIColor?

    public init(fill: UIColor, border: UIColor?) {
        self.fill = fill
        self.border = border
    }

    public static let control = GiftFlat(fill: UIColor(white: 1.0, alpha: 0.18), border: UIColor(white: 1.0, alpha: 0.26))

    public func mixed(with other: GiftFlat, alpha: CGFloat) -> GiftFlat {
        let fill = GiftFlat.mix(self.fill, other.fill, alpha)
        var border: UIColor?
        if self.border != nil || other.border != nil {
            let from = self.border ?? (other.border ?? .clear).withAlphaComponent(0.0)
            let to = other.border ?? (self.border ?? .clear).withAlphaComponent(0.0)
            border = GiftFlat.mix(from, to, alpha)
        }
        return GiftFlat(fill: fill, border: border)
    }

    // OKLab avoids the muddy grey midpoint of an sRGB cross-fade.
    private static func mix(_ a: UIColor, _ b: UIColor, _ p: CGFloat) -> UIColor {
        return a.mixedOKLab(with: b, alpha: p)
    }
}

public class GiftFlatTonalView: UIView {
    public private(set) var flat: GiftFlat = .control
    public private(set) var radius: CGFloat = 0.0
    public var action: (() -> Void)? {
        didSet {
            self.press.isEnabled = self.action != nil
            self.isAccessibilityElement = self.action != nil
        }
    }
    public var label: String? {
        didSet {
            self.accessibilityLabel = self.label
        }
    }
    private let rim = GiftRimView()
    private let press = UILongPressGestureRecognizer()
    private var isPressed = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.layer.cornerCurve = .continuous
        self.addSubview(self.rim)
        self.press.addTarget(self, action: #selector(self.pressed(_:)))
        self.press.minimumPressDuration = 0.0
        self.press.isEnabled = false
        self.addGestureRecognizer(self.press)
        self.accessibilityTraits = .button
    }

    public override func accessibilityActivate() -> Bool {
        guard let action = self.action else {
            return false
        }
        action()
        return true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // radius nil: capsule.
    public func update(flat: GiftFlat, radius: CGFloat? = nil, transition: ComponentTransition = .immediate) {
        let radius = radius ?? min(self.bounds.width, self.bounds.height) / 2.0
        self.flat = flat
        self.radius = radius
        transition.setBackgroundColor(view: self, color: flat.fill)
        transition.setCornerRadius(layer: self.layer, cornerRadius: radius)
        self.updateRim(transition: .immediate)
    }

    // A capsule takes its radius from the bounds, so set the frame first.
    public func update(tile: GiftStatsTileSurface, shape: GiftStatsTileStyle.Shape = .tile, transition: ComponentTransition = .immediate) {
        switch shape {
        case .tile:
            self.update(flat: tile.flat, radius: GiftStatsTileStyle.radius, transition: transition)
        case .capsule:
            self.update(flat: tile.flat, radius: nil, transition: transition)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        self.updateRim(transition: .immediate)
    }

    // Pass the target size when animating a size change so the rim follows it.
    public func updateRim(size: CGSize? = nil, transition: ComponentTransition) {
        let size = size ?? self.bounds.size
        self.rim.frame = CGRect(origin: .zero, size: size)
        self.rim.isHidden = self.flat.rimStrength <= 0.0
        self.rim.update(size: size, cornerRadius: self.radius, strength: self.flat.rimStrength, transition: transition)
    }

    public func morphLook(in card: UIView) -> GiftMorphLook {
        return GiftMorphLook(frame: self.convert(self.bounds, to: card), radius: self.radius, flat: self.flat)
    }

    @objc private func pressed(_ recognizer: UILongPressGestureRecognizer) {
        let inside = self.bounds.insetBy(dx: -10.0, dy: -10.0).contains(recognizer.location(in: self))
        switch recognizer.state {
        case .began:
            self.isPressed = true
            self.rim.holdLive(for: 0.8)
            if !GiftStatsEnvironment.reduceMotion {
                UIView.animate(withDuration: 0.16, delay: 0.0, options: [.beginFromCurrentState, .allowUserInteraction], animations: {
                    self.transform = CGAffineTransform(scaleX: 0.95, y: 0.93)
                })
            }
        case .changed:
            if !inside && self.isPressed {
                self.isPressed = false
                self.release()
            }
        case .ended:
            let fire = self.isPressed && inside
            self.isPressed = false
            self.release()
            if fire {
                self.action?()
            }
        default:
            self.isPressed = false
            self.release()
        }
    }

    private func release() {
        // Keep the rim live until the spring-back settles.
        self.rim.holdLive(for: 0.8)
        guard !GiftStatsEnvironment.reduceMotion else {
            self.layer.removeAllAnimations()
            self.transform = .identity
            return
        }
        UIView.animate(withDuration: 0.46, delay: 0.0, usingSpringWithDamping: 0.82, initialSpringVelocity: 1.6, options: [.beginFromCurrentState, .allowUserInteraction], animations: {
            self.transform = .identity
        })
    }
}
