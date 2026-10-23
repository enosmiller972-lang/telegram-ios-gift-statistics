import Foundation
import UIKit
import ComponentFlow
import GiftStats

private enum GiftRimTune {
    static let strokeWidth: CGFloat = 1.0
    // Top-left/bottom-right peak, the other two corners, and the middle of the sides.
    static let cornerPeak: CGFloat = 0.60
    static let cornerOther: CGFloat = 0.26
    static let floor: CGFloat = 0.04
    static let lightWidth: CGFloat = 1.2
    static let lightAlpha: CGFloat = 0.30
}

// Glass rim: a conic-gradient stroke (built in a square, stretched to the shape) plus a light crescent at the top-left,
// both plus-lighter. Live while changing, rasterized once it has been still for settleDelay.
final class GiftRimView: UIView {
    private static let side: CGFloat = 100.0
    private static let settleDelay: Double = 0.3

    private let sweepHost = CALayer()
    private let sweep = CAGradientLayer()
    private let ring = CALayer()

    private let lightHost = CALayer()
    private let lightFade = CAGradientLayer()
    private let light = CAShapeLayer()
    private let lightClip = CALayer()

    private var applied: (size: CGSize, radius: CGFloat, strength: CGFloat)?

    private let isCacheable: Bool
    private var isCached = false
    private var settleAt: CFTimeInterval = 0.0
    private var isSettleScheduled = false

    init(isCacheable: Bool = true) {
        self.isCacheable = isCacheable
        super.init(frame: .zero)
        self.isUserInteractionEnabled = false

        self.sweep.type = .conic
        self.sweep.bounds = CGRect(origin: .zero, size: CGSize(width: GiftRimView.side, height: GiftRimView.side))
        self.sweep.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.sweep.endPoint = CGPoint(x: 1.0, y: 0.5)
        self.sweepHost.addSublayer(self.sweep)
        self.ring.cornerCurve = .continuous
        self.ring.borderColor = UIColor.black.cgColor
        self.sweepHost.mask = self.ring
        self.sweepHost.compositingFilter = "plusL"
        self.layer.addSublayer(self.sweepHost)

        GiftRimView.setUpCrescent(host: self.lightHost, fade: self.lightFade, crescent: self.light, clip: self.lightClip, color: .white, filter: "plusL", from: CGPoint(x: 0.0, y: 0.0), to: CGPoint(x: 1.0, y: 1.0))
        self.layer.addSublayer(self.lightHost)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func setUpCrescent(host: CALayer, fade: CAGradientLayer, crescent: CAShapeLayer, clip: CALayer, color: UIColor, filter: String, from: CGPoint, to: CGPoint) {
        fade.startPoint = from
        fade.endPoint = to
        fade.colors = [UIColor(white: 0.0, alpha: 1.0).cgColor, UIColor(white: 0.0, alpha: 0.3).cgColor]
        fade.locations = [0.0, 0.8]
        host.mask = fade
        host.compositingFilter = filter
        crescent.fillColor = color.cgColor
        crescent.fillRule = .evenOdd
        clip.backgroundColor = UIColor.black.cgColor
        clip.cornerCurve = .continuous
        crescent.mask = clip
        host.addSublayer(crescent)
    }

    // 0 degrees is the middle of the right side, clockwise.
    private static func sweepAlpha(degrees: CGFloat) -> CGFloat {
        // Bottom-right 45, bottom-left 135, top-left 225, top-right 315.
        let corners: [(angle: CGFloat, alpha: CGFloat)] = [(45.0, GiftRimTune.cornerPeak), (135.0, GiftRimTune.cornerOther), (225.0, GiftRimTune.cornerPeak), (315.0, GiftRimTune.cornerOther)]
        var alpha = GiftRimTune.floor
        for corner in corners {
            var distance = abs(degrees - corner.angle)
            distance = min(distance, 360.0 - distance)
            if distance < 45.0 {
                let falloff = cos(distance / 45.0 * CGFloat.pi / 2.0)
                alpha = max(alpha, GiftRimTune.floor + (corner.alpha - GiftRimTune.floor) * falloff * falloff)
            }
        }
        return alpha
    }

    func update(size: CGSize, cornerRadius: CGFloat, strength: CGFloat, transition: ComponentTransition = .immediate) {
        if let applied = self.applied, applied.size == size, applied.radius == cornerRadius, applied.strength == strength {
            return
        }
        let isShapeChanged = self.applied?.size != size || self.applied?.radius != cornerRadius
        self.applied = (size, cornerRadius, strength)
        self.holdLive(for: GiftRimView.settleDelay + GiftRimView.duration(of: transition))
        let bounds = CGRect(origin: .zero, size: size)
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if self.sweep.colors == nil {
            let steps = 24
            self.sweep.colors = (0 ... steps).map { UIColor(white: 1.0, alpha: GiftRimView.sweepAlpha(degrees: 360.0 * CGFloat($0) / CGFloat(steps))).cgColor }
            self.sweep.locations = (0 ... steps).map { NSNumber(value: Double($0) / Double(steps)) }
            self.ring.borderWidth = GiftRimTune.strokeWidth
            self.light.opacity = Float(GiftRimTune.lightAlpha)
        }
        self.sweepHost.opacity = Float(strength)
        self.lightHost.opacity = Float(strength)
        if isShapeChanged {
            self.sweepHost.frame = bounds
            self.lightHost.frame = bounds
            self.lightFade.frame = bounds
            self.light.frame = bounds
            self.lightClip.frame = bounds
            self.lightClip.cornerRadius = cornerRadius
            let outer = bounds.insetBy(dx: -40.0, dy: -40.0)
            let lightInner = UIBezierPath(roundedRect: bounds.offsetBy(dx: GiftRimTune.lightWidth, dy: GiftRimTune.lightWidth), cornerRadius: cornerRadius)
            lightInner.append(UIBezierPath(rect: outer))
            self.light.path = lightInner.cgPath
        }

        // Inside the disabled-actions transaction: these standalone layers would otherwise get implicit 0.25 s animations
        // that an immediate transition doesn't suppress, and a per-frame morph rim would lag its size.
        transition.setBounds(layer: self.ring, bounds: bounds)
        transition.setPosition(layer: self.ring, position: center)
        transition.setCornerRadius(layer: self.ring, cornerRadius: cornerRadius)
        transition.setPosition(layer: self.sweep, position: center)
        transition.setTransform(layer: self.sweep, transform: CATransform3DMakeScale(size.width / GiftRimView.side, size.height / GiftRimView.side, 1.0))
        CATransaction.commit()
    }

    private static func duration(of transition: ComponentTransition) -> Double {
        if case let .curve(duration, _) = transition.animation {
            return duration
        }
        return 0.0
    }

    // Call when the rim or its surface changes or moves.
    func holdLive(for seconds: Double) {
        if self.isCached {
            self.isCached = false
            self.layer.shouldRasterize = false
        }
        self.settleAt = max(self.settleAt, CACurrentMediaTime() + seconds)
        self.scheduleSettle()
    }

    private func scheduleSettle() {
        guard self.isCacheable, !self.isSettleScheduled else {
            return
        }
        self.isSettleScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.0, self.settleAt - CACurrentMediaTime()) + 0.01) { [weak self] in
            self?.settle()
        }
    }

    private func settle() {
        self.isSettleScheduled = false
        if self.settleAt > CACurrentMediaTime() {
            self.scheduleSettle()
            return
        }
        self.rasterize()
    }

    // Saves the mask and blend passes every frame. Skipped when not pixel-aligned, as the bitmap would be resampled.
    private func rasterize() {
        guard self.isCacheable, !self.isCached, !self.isHidden, self.applied != nil, let window = self.window else {
            return
        }
        let scale = window.screen.scale
        let origin = self.layer.convert(CGPoint.zero, to: window.layer)
        let isWhole = [origin.x, origin.y, self.bounds.width, self.bounds.height].allSatisfy { abs($0 * scale - ($0 * scale).rounded()) < 0.02 }
        guard isWhole else {
            return
        }
        self.layer.rasterizationScale = scale
        self.layer.shouldRasterize = true
        self.isCached = true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if self.window != nil && !self.isCached {
            self.holdLive(for: GiftRimView.settleDelay)
        }
    }

}
