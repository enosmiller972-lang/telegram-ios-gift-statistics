import Foundation
import UIKit

/// A sales row in the card morph: a snapshot without the price, plus the live price views.
extension GiftStatsSalesRowView {
    func morphPicture() -> UIView? {
        let parts: [UIView] = [self.glyph, self.price]
        let wasHidden = parts.map { $0.isHidden }
        for part in parts {
            part.isHidden = true
        }
        defer {
            for (part, hidden) in zip(parts, wasHidden) {
                part.isHidden = hidden
            }
        }
        return GiftMorphCapture.picture(of: self)
    }

    /// Moves the live glyph and price into a row-sized wrapper for the morph and back on release.
    func morphPriceThing(path: GiftMorphThing.Path, in card: UIView, isFrozen: Bool) -> GiftMorphThing {
        let wrapper = UIView(frame: CGRect(origin: .zero, size: self.bounds.size))
        wrapper.isUserInteractionEnabled = false
        let frame = self.convert(self.bounds, to: card)
        return GiftMorphThing(
            view: wrapper,
            path: path,
            home: { [weak self] in
                return isFrozen ? frame : (self?.convert(self?.bounds ?? .zero, to: card) ?? frame)
            },
            activate: { [weak self] in
                guard let self else {
                    return
                }
                wrapper.addSubview(self.glyph)
                wrapper.addSubview(self.price)
            },
            release: { [weak self] in
                guard let self else {
                    return
                }
                self.addSubview(self.glyph)
                self.addSubview(self.price)
            }
        )
    }
}
