import Foundation
import UIKit

// GiftMorphPair.dissolves: stats content shrinks and fades in place while card content fades in over it.
extension GiftMorphPiece {
    func layoutDissolved(frame: CGRect, a: GiftMorphLook, b: GiftMorphLook, p: CGFloat, center: CGPoint, time: CGFloat) {
        let middle = CGPoint(x: frame.width / 2.0, y: frame.height / 2.0)
        let present = GiftMorphPiece.smooth((self.shrinks ? GiftMorphTiming.dissolveOutSmall : GiftMorphTiming.dissolveOut).progress(at: time))
        let scale = 1.0 - (1.0 - GiftMorphTiming.dissolveScale) * (1.0 - present)
        for thing in self.statsThings {
            let rect = self.rect(of: thing, isCard: false, a: a, b: b, p: p, center: center)
            let spot = CGPoint(x: rect.midX - frame.minX, y: rect.midY - frame.minY)
            thing.view.center = CGPoint(x: middle.x + (spot.x - middle.x) * scale, y: middle.y + (spot.y - middle.y) * scale)
            thing.view.transform = CGAffineTransform(scaleX: scale, y: scale)
            thing.view.alpha = present
        }
        let arrived = 1.0 - GiftMorphPiece.smooth((self.shrinks ? GiftMorphTiming.dissolveInSmall : GiftMorphTiming.dissolveIn).progress(at: time))
        for thing in self.cardThings {
            let rect = self.rect(of: thing, isCard: true, a: a, b: b, p: p, center: center)
            thing.view.center = CGPoint(x: rect.midX - frame.minX, y: rect.midY - frame.minY)
            thing.view.transform = .identity
            thing.view.alpha = arrived
        }
    }
}

extension GiftMorphPiece {
    func layoutBorn(frame: CGRect, a: GiftMorphLook, b: GiftMorphLook, p: CGFloat, center: CGPoint, time: CGFloat) {
        let arrived = 1.0 - GiftMorphPiece.smooth(GiftMorphTiming.bornContent.progress(at: time))
        for thing in self.cardThings {
            let rect = self.rect(of: thing, isCard: true, a: a, b: b, p: p, center: center)
            thing.view.center = CGPoint(x: rect.midX - frame.minX, y: rect.midY - frame.minY)
            thing.view.transform = .identity
            thing.view.alpha = arrived
        }
    }
}

extension GiftMorphPiece {
    func layoutFadedOut(frame: CGRect, a: GiftMorphLook, b: GiftMorphLook, p: CGFloat, center: CGPoint, gone: CGFloat) {
        for thing in self.statsThings {
            let rect = self.rect(of: thing, isCard: false, a: a, b: b, p: p, center: center)
            thing.view.center = CGPoint(x: rect.midX - frame.minX, y: rect.midY - frame.minY)
            thing.view.transform = .identity
            thing.view.alpha = 1.0 - gone
        }
    }
}

// GiftMorphPair.ridesBelow: a bodiless piece that follows the bottom edge of edgeHost.
extension GiftMorphPiece {
    func riding(_ frame: CGRect, at moment: GiftMorphMoment) -> CGRect {
        guard self.ridesBelow != nil, let host = self.edgeHost else {
            return frame
        }
        var rect = frame
        rect.origin.y += host.cardFrame(at: moment).maxY - host.looks().card.frame.maxY
        return rect
    }

    func layoutRiding(frame: CGRect, a: GiftMorphLook, b: GiftMorphLook, p: CGFloat, center: CGPoint, time: CGFloat) {
        let arrived = 1.0 - GiftMorphPiece.smooth(GiftMorphTiming.line.progress(at: time))
        for thing in self.cardThings {
            let rect = self.rect(of: thing, isCard: true, a: a, b: b, p: p, center: center)
            thing.view.center = CGPoint(x: rect.midX - frame.minX, y: rect.midY - frame.minY)
            thing.view.transform = .identity
            thing.view.alpha = arrived
        }
    }
}
