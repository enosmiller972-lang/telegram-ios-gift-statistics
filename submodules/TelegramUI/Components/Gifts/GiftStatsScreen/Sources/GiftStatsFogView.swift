import Foundation
import UIKit
import Display
import EdgeEffect
import GlassBackgroundComponent

/// Variable blur over the last row of the closed sales log, from none at the top to `maxBlurRadius` at the bottom.
final class GiftStatsFogView: UIView {
    /// About 9 pt of Gaussian sigma on screen (`GiftStatsFogBake.sigmaPerRadius`).
    static let maxBlurRadius: CGFloat = 5.5

    private let layerDelegate = SimpleLayerDelegate()
    private var effect: VariableBlurEffect?
    private let backdrop: CALayer?
    private var appliedSize: CGSize?
    private var isShown = false

    var isShownNow: Bool {
        return self.isShown
    }

    override init(frame: CGRect) {
        self.backdrop = createBackdropLayer()
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.isHidden = true
        self.alpha = 0.0
        self.clipsToBounds = true
        self.layer.cornerCurve = .continuous
        self.layer.cornerRadius = GiftTonalPalette.cornerRadius
        self.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        if let backdrop = self.backdrop {
            backdrop.delegate = self.layerDelegate
            backdrop.setValue(0.5, forKey: "scale")
            self.layer.addSublayer(backdrop)
            self.effect = VariableBlurEffect(layer: backdrop, maxBlurRadius: GiftStatsFogView.maxBlurRadius)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(size: CGSize) {
        guard self.appliedSize != size, size.width > 0.0, size.height > 0.0 else {
            return
        }
        self.appliedSize = size
        let gradient = VariableBlurEffect.Gradient(height: size.height, alpha: [], positions: [])
        self.effect?.update(size: size, constantHeight: size.height, placement: VariableBlurEffect.Placement(position: .bottom, inwardsExtension: 0.0), gradient: gradient, transition: .immediate)
    }

    /// Hidden while faded out so no backdrop is kept alive.
    func setShown(_ shown: Bool, duration: Double) {
        guard self.isShown != shown else {
            return
        }
        self.isShown = shown
        if shown {
            self.isHidden = false
            if duration <= 0.0 {
                self.alpha = 1.0
                return
            }
            UIView.animate(withDuration: duration, delay: 0.0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut], animations: {
                self.alpha = 1.0
            })
        } else {
            if duration <= 0.0 {
                self.alpha = 0.0
                self.isHidden = true
                return
            }
            UIView.animate(withDuration: duration, delay: 0.0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut], animations: {
                self.alpha = 0.0
            }, completion: { [weak self] _ in
                if let self, !self.isShown {
                    self.isHidden = true
                }
            })
        }
    }
}
