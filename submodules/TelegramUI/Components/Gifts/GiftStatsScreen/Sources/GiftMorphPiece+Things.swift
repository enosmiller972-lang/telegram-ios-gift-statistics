import Foundation
import UIKit

extension GiftMorphPiece {
    func layoutThings(frame: CGRect, a: GiftMorphLook, b: GiftMorphLook, p: CGFloat, time: CGFloat, gone: CGFloat) {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if self.fadesOutInPlace {
            self.layoutFadedOut(frame: frame, a: a, b: b, p: p, center: center, gone: gone)
            return
        }
        if self.dissolves {
            self.layoutDissolved(frame: frame, a: a, b: b, p: p, center: center, time: time)
            return
        }
        if self.isBorn {
            self.layoutBorn(frame: frame, a: a, b: b, p: p, center: center, time: time)
            return
        }
        if self.ridesBelow != nil {
            self.layoutRiding(frame: frame, a: a, b: b, p: p, center: center, time: time)
            return
        }
        let maxCard = self.cardThings.map { $0.view.bounds.height }.max() ?? 0.0
        let maxStats = self.statsThings.map { $0.view.bounds.height }.max() ?? 0.0
        for (number, cell) in self.cells {
            let cardRow = self.cardThings.first(where: { $0.path == .row(number) })
            let statsRow = self.statsThings.first(where: { $0.path == .row(number) })
            guard let thing = cardRow ?? statsRow else {
                continue
            }
            let rect = self.rect(of: thing, isCard: cardRow != nil, a: a, b: b, p: p, center: center)
            let from = cardRow?.view.bounds.height ?? 0.0
            let to = statsRow?.view.bounds.height ?? 0.0
            // A row without a counterpart closes in the first half (or opens in the second).
            var height = GiftMorphPiece.lerp(from, to, p)
            if statsRow == nil {
                height = from * (1.0 - GiftMorphPiece.smooth(p / 0.5))
            } else if cardRow == nil {
                height = to * GiftMorphPiece.smooth((p - 0.5) / 0.5)
            }
            cell.frame = CGRect(x: rect.minX - frame.minX, y: rect.midY - height / 2.0 - frame.minY, width: rect.width, height: height)
        }
        // Reel: card content slides up and out while stats content comes in from below.
        for thing in self.cardThings {
            let push = self.push(of: thing, partner: self.statsThings, own: maxCard, other: maxStats, time: time)
            self.place(thing, push: -push.distance * push.progress, fadeOut: push.fadeOut, frame: frame, a: a, b: b, p: p, center: center, isCard: true)
        }
        for thing in self.statsThings {
            if self.mergesIntoTop {
                let alpha = GiftMorphPiece.smooth(GiftMorphTiming.merge.progress(at: time))
                self.place(thing, push: 0.0, fadeOut: 1.0 - alpha, frame: frame, a: a, b: b, p: p, center: center, isCard: false)
                continue
            }
            let push = self.push(of: thing, partner: self.cardThings, own: maxStats, other: maxCard, time: time)
            self.place(thing, push: push.distance * (1.0 - push.progress), fadeOut: 1.0 - push.fadeIn, frame: frame, a: a, b: b, p: p, center: center, isCard: false)
        }
    }

    func place(_ thing: GiftMorphThing, push: CGFloat, fadeOut: CGFloat, frame: CGRect, a: GiftMorphLook, b: GiftMorphLook, p: CGFloat, center: CGPoint, isCard: Bool) {
        let rect = self.rect(of: thing, isCard: isCard, a: a, b: b, p: p, center: center)
        if case let .row(number) = thing.path, let cell = self.cells[number] {
            // The cell clips the row, so no fade.
            thing.view.center = CGPoint(x: cell.bounds.width / 2.0, y: cell.bounds.height / 2.0 + push)
            thing.view.alpha = 1.0
        } else {
            thing.view.center = CGPoint(x: rect.midX - frame.minX, y: rect.midY - frame.minY + push)
            thing.view.alpha = 1.0 - fadeOut
        }
        thing.view.transform = .identity
    }

    // The distance is half of each height, so the outgoing and incoming content touch but never overlap.
    func push(of thing: GiftMorphThing, partner: [GiftMorphThing], own: CGFloat, other: CGFloat, time: CGFloat) -> (distance: CGFloat, progress: CGFloat, fadeOut: CGFloat, fadeIn: CGFloat) {
        var height = thing.view.bounds.height
        var partnerHeight = other > 0.0 ? other : height
        var order: CGFloat = 0.0
        if case let .row(number) = thing.path {
            order = CGFloat(number) * GiftMorphTiming.rowStep
            if let match = partner.first(where: { $0.path == .row(number) }) {
                partnerHeight = match.view.bounds.height
            }
        } else {
            height = own > 0.0 ? own : height
        }
        let t = GiftMorphWindow(start: self.window.start + order, length: self.window.length).progress(at: time)
        let progress = t * t * (3.0 - 2.0 * t)
        let distance = (height + partnerHeight) / 2.0
        return (distance, progress, GiftMorphPiece.smooth((t - 0.55) / 0.45), GiftMorphPiece.smooth((t - 0.1) / 0.5))
    }

    func rect(of thing: GiftMorphThing, isCard: Bool, a: GiftMorphLook, b: GiftMorphLook, p: CGFloat, center: CGPoint) -> CGRect {
        let home = thing.home()
        switch thing.path {
        case .rigid:
            let origin = isCard ? a.frame : b.frame
            return home.offsetBy(dx: center.x - origin.midX, dy: center.y - origin.midY)
        case let .row(number):
            let others = isCard ? self.statsThings : self.cardThings
            if let counterpart = others.first(where: { $0.path == .row(number) })?.home() {
                return isCard ? GiftMorphPiece.lerp(home, counterpart, p) : GiftMorphPiece.lerp(counterpart, home, p)
            }
            // No counterpart: continue as the next row after the other table's last one.
            var last: (number: Int, home: CGRect)?
            for other in others {
                if case let .row(index) = other.path, index > (last?.number ?? -1) {
                    last = (index, other.home())
                }
            }
            let step = last.map { CGFloat(number - $0.number) * $0.home.height } ?? 0.0
            let target = (last?.home ?? home).offsetBy(dx: 0.0, dy: step)
            return isCard ? GiftMorphPiece.lerp(home, target, p) : GiftMorphPiece.lerp(target, home, p)
        case let .trailing(inset):
            if isCard {
                let goal = CGRect(x: b.frame.maxX - inset - home.width / 2.0, y: b.frame.midY - home.height / 2.0, width: home.width, height: home.height)
                return GiftMorphPiece.lerp(home, goal, p)
            }
            let origin = CGRect(x: a.frame.maxX - inset - home.width / 2.0, y: a.frame.midY - home.height / 2.0, width: home.width, height: home.height)
            return GiftMorphPiece.lerp(origin, home, p)
        }
    }
}
