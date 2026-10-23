import Foundation
import UIKit
import Display
import GiftStatsScreen
import GiftStats

/// Card-owned parts of the card <-> stats morph (gift, title, lines, button fades), driven by the card progress from `GiftMorph`.
/// The gift name moves into the collection name (gaining its ending, e.g. the plural "s") while the number fades out.
final class GiftViewStatsFlow {
    private let parts: GiftViewStatsParts
    private let stats: GiftStatsMorph
    private let giftTransform: CGAffineTransform
    /// Scroll offset of the stats when returning: the card jumps to its place and the gift glides from its on-screen position.
    private let carried: CGFloat
    /// Extra gift-to-title spacing of the card over the stats. Applied late so a header scrolling in from above arrives as one piece.
    private let headerSpread: CGFloat
    /// The "Buy" fades are laid out for the final height; they are pinned to the animating bottom edge to avoid a hard band mid-card.
    private let heights: (card: CGFloat, stats: CGFloat)
    private let fadeBottoms: [(view: UIView, bottom: CGFloat)]
    /// Moving gift name, the collection name ending that fades in, and the number that fades out.
    private var name: UIView?
    private var ending: UIView?
    private var tail: UIView?
    private var nameFrom = CGPoint.zero
    private var nameTo = CGPoint.zero
    private var tailFrom = CGPoint.zero
    /// See `GiftViewStatsBorn`; nil when the gift glides.
    private let born: GiftViewStatsBorn?
    var bornBand: ClosedRange<CGFloat>? {
        return self.born?.band
    }

    private static let pulse: CGFloat = 0.03

    private static func smooth(_ value: CGFloat) -> CGFloat {
        let t = min(1.0, max(0.0, value))
        return t * t * (3.0 - 2.0 * t)
    }

    /// `startHeight` is the card height before the layout for the target state. `isHeaderBorn`: the stats header is scrolled out (return only).
    init(parts: GiftViewStatsParts, stats: GiftStatsMorph, card: UIView, toStats: Bool, startHeight: CGFloat, carried: CGFloat = 0.0, isHeaderBorn: Bool = false) {
        self.parts = parts
        self.born = !toStats && isHeaderBorn ? GiftViewStatsBorn(parts: parts, stats: stats, card: card) : nil
        self.stats = stats
        self.heights = toStats ? (startHeight, card.bounds.height) : (card.bounds.height, startHeight)
        self.fadeBottoms = (stats.fades + (parts.fade.map { [$0] } ?? [])).map { ($0, $0.frame.maxY) }
        self.giftTransform = parts.giftTransform()
        self.carried = carried
        var spread: CGFloat = 0.0
        if let gift = parts.gift, let title = parts.title {
            spread = max(0.0, title.center.y - gift.center.y - (GiftStatsHeaderMetrics.titleCenterY - GiftStatsHeaderMetrics.giftCenterY))
        }
        // Ramps in over the first 150pt of scroll.
        self.headerSpread = spread * min(1.0, abs(carried) / 150.0)
        if !toStats {
            parts.letGo(parts.others + (parts.fade.map { [$0] } ?? []))
        }
        guard let cardTitle = parts.title, let statsTitle = stats.title else {
            return
        }
        let cardFrame = toStats ? parts.titleFrame : cardTitle.convert(cardTitle.bounds, to: card)
        let statsFrame = statsTitle.convert(statsTitle.bounds, to: card)
        parts.keepHidden([cardTitle])
        statsTitle.alpha = 0.0
        // A card title scrolled out of the card has no target; the real title appears at the end.
        guard card.bounds.intersects(cardFrame), let image = (parts.titlePicture as? UIImageView)?.image,
              let name = GiftMorphCapture.withShown([statsTitle], { GiftMorphCapture.picture(of: statsTitle) }) else {
            return
        }
        // The gift name is the first `titleStem` points of the collection name; after it come the number (card) or the ending (stats).
        let width = min(cardFrame.width, statsFrame.width, stats.titleStem)
        let holder = UIView(frame: CGRect(origin: .zero, size: statsFrame.size))
        holder.isUserInteractionEnabled = false
        let nameImage = (name as? UIImageView)?.image
        let ending = GiftViewStatsFlow.slice(of: UIImageView(image: nameImage), from: width, to: statsFrame.width, height: statsFrame.height)
        holder.addSubview(GiftViewStatsFlow.slice(of: UIImageView(image: nameImage), from: 0.0, to: width, height: statsFrame.height))
        holder.addSubview(ending)
        self.nameFrom = CGPoint(x: cardFrame.minX + statsFrame.width / 2.0, y: cardFrame.midY)
        self.nameTo = CGPoint(x: statsFrame.midX, y: statsFrame.midY)
        holder.center = self.nameFrom
        let tail = GiftViewStatsFlow.slice(of: UIImageView(image: image), from: width, to: cardFrame.width, height: cardFrame.height)
        tail.frame.origin = CGPoint(x: cardFrame.minX + width, y: cardFrame.minY)
        self.tailFrom = tail.center
        card.addSubview(tail)
        card.addSubview(holder)
        self.name = holder
        self.ending = ending
        self.tail = tail
    }

    private static func slice(of picture: UIView, from: CGFloat, to: CGFloat, height: CGFloat) -> UIView {
        let view = UIView(frame: CGRect(x: from, y: 0.0, width: max(0.0, to - from), height: height))
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        picture.frame = CGRect(x: -from, y: 0.0, width: picture.bounds.width, height: height)
        view.addSubview(picture)
        return view
    }

    /// Positions follow `moment.position`, fades follow `moment.time` (`GiftMorphTiming` windows).
    func apply(_ moment: GiftMorphMoment) {
        let s = min(1.0, max(0.0, moment.position))
        // Small pulse as the symbols arrive; the symbols themselves follow the transform without it.
        let pulse = 1.0 + GiftViewStatsFlow.pulse * sin(CGFloat.pi * GiftMorphTiming.symbolsArrive.progress(at: moment.time))
        if let born = self.born {
            self.applyBorn(born, moment: moment, pulse: pulse)
        } else {
            self.applyGlide(moment: moment, pulse: pulse)
        }
        self.parts.setCraftLevel(GiftViewStatsFlow.smooth(s), symbolsFlow: true)
        self.parts.setSymbolsFlow(GiftMorphTiming.symbols.progress(at: moment.time))
        let buy = GiftViewStatsFlow.smooth(GiftMorphTiming.buyFade.progress(at: moment.time))
        self.parts.fade?.alpha = 1.0 - buy
        let height = self.heights.card + (self.heights.stats - self.heights.card) * s
        for (view, bottom) in self.fadeBottoms {
            // Override the card's own fade animation; the position is driven here.
            view.layer.removeAllAnimations()
            view.transform = CGAffineTransform(translationX: 0.0, y: height - bottom)
        }
        for view in self.stats.fades {
            view.alpha = buy
        }
    }

    private func applyGlide(moment: GiftMorphMoment, pulse: CGFloat) {
        let s = min(1.0, max(0.0, moment.position))
        let scale = 1.0 + (self.giftTransform.a - 1.0) * s
        if let gift = self.parts.gift {
            // Keep the stats spacing until the last third, see `headerSpread`.
            let lift = (self.giftTransform.ty + self.carried) * s + self.headerSpread * ((1.0 - s) - GiftViewStatsFlow.smooth((0.35 - s) / 0.35))
            let transform = CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: 0.0, y: lift))
            gift.transform = CGAffineTransform(scaleX: scale * pulse, y: scale * pulse).concatenating(CGAffineTransform(translationX: 0.0, y: lift))
            self.parts.moveSymbols(for: transform)
        }
        let out = 1.0 - GiftViewStatsFlow.smooth(GiftMorphTiming.title.progress(at: moment.time))
        if let name = self.name {
            let center = CGPoint(x: self.nameFrom.x + (self.nameTo.x - self.nameFrom.x) * s, y: self.nameFrom.y + (self.nameTo.y - self.nameFrom.y) * s)
            name.center = center
            self.tail?.center = CGPoint(x: self.tailFrom.x + center.x - self.nameFrom.x, y: self.tailFrom.y + center.y - self.nameFrom.y)
            // When coming in from above, show the title only once it is well inside, so it doesn't appear before the gift.
            let inside = GiftViewStatsFlow.smooth((center.y - 40.0) / 70.0)
            name.alpha = inside
            // The ending replaces the number, so it appears once the number is half gone.
            self.ending?.alpha = GiftViewStatsFlow.smooth((0.5 - out) / 0.5)
            self.tail?.alpha = out * inside
        }
        for view in self.parts.others {
            view.alpha = out
        }
    }

    private func applyBorn(_ born: GiftViewStatsBorn, moment: GiftMorphMoment, pulse: CGFloat) {
        let pose = born.pose(at: moment.time)
        if let gift = self.parts.gift {
            let shift = CGAffineTransform(translationX: pose.shift.x, y: pose.shift.y)
            let transform = CGAffineTransform(scaleX: pose.scale, y: pose.scale).concatenating(shift)
            gift.transform = CGAffineTransform(scaleX: pose.scale * pulse, y: pose.scale * pulse).concatenating(shift)
            gift.alpha = pose.travel
            self.parts.moveSymbols(for: transform)
        }
        let title = born.titleShift(pose: pose)
        if let name = self.name {
            name.center = CGPoint(x: self.nameFrom.x + title.x, y: self.nameFrom.y + title.y)
            name.alpha = pose.title
            self.ending?.alpha = 0.0
            self.tail?.center = CGPoint(x: self.tailFrom.x + title.x, y: self.tailFrom.y + title.y)
            self.tail?.alpha = pose.title
        }
        for line in born.lines {
            let shift = born.shift(below: line.offset, pose: pose)
            line.view.transform = CGAffineTransform(translationX: shift.x, y: shift.y)
            line.view.alpha = pose.title
        }
    }

    func finish(toStats: Bool) {
        self.name?.removeFromSuperview()
        self.tail?.removeFromSuperview()
        self.name = nil
        self.ending = nil
        self.tail = nil
        let lines = self.parts.others + (self.parts.fade.map { [$0] } ?? [])
        let end: CGFloat = toStats ? 1.0 : 0.0
        self.apply(GiftMorphMoment(position: end, time: end))
        for (view, _) in self.fadeBottoms {
            view.transform = .identity
        }
        self.parts.setSymbolsFlow(nil)
        self.parts.setCraftLevel(end)
        self.parts.setCraftShift(0.0)
        if toStats {
            self.parts.keepHidden(lines)
            self.stats.title?.alpha = 1.0
        } else {
            let cardLines = self.parts.title.map { [$0] } ?? []
            self.parts.letGo(lines + cardLines)
            for view in lines + cardLines {
                view.alpha = 1.0
            }
        }
    }
}
