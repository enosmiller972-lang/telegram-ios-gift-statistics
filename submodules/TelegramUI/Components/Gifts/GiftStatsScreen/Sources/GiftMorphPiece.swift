import Foundation
import UIKit
import Display
import ComponentFlow
import GiftStats

// One flat surface of the morph and the content clipped to it. Content is swapped by a reel-like push in the
// piece's own GiftMorphTiming window. Everything is a function of the moment, so the way back is the reverse.
final class GiftMorphPiece {
    private static let thickness: CGFloat = 8.0
    private static let surfaceWindow: CGFloat = 0.4
    private static let swapOut: CGFloat = 0.45
    private static let swapIn: CGFloat = 0.55

    private(set) var isLanded = false
    var onLanding: (() -> Void)?

    private let flatBody = UIView()
    private let flatRim = GiftRimView(isCacheable: false)
    private let clip = UIView()
    private let card: GiftMorphEnd?
    private let stats: GiftMorphEnd?
    private let anchor: GiftMorphEnd
    private let near: GiftMorphEnd?
    private let emerges: Bool
    let window: GiftMorphWindow
    private let toStats: Bool
    private let hasCardSurface: Bool
    private let hasStatsSurface: Bool
    private let goesOutInPlace: Bool
    private let comesInInPlace: Bool
    // Hidden until it separates from the neighbour; two overlapping rims would look like one brighter rim.
    private let growsOutOfNeighbour: Bool
    private let fillsInWindow: Bool
    let cardThings: [GiftMorphThing]
    let statsThings: [GiftMorphThing]
    let dissolves: Bool
    let isBorn: Bool
    let shrinks: Bool
    // Uses its own ease finished halfway back instead of the card height.
    private let isQuick: Bool
    private let mergesInto: GiftMorphEnd?
    let fadesOutInPlace: Bool
    let ridesBelow: GiftMorphEnd?
    // Set by GiftMorph once all pieces exist.
    weak var edgeHost: GiftMorphPiece?
    var mergesIntoTop: Bool {
        return self.mergesInto != nil
    }
    // Each table row gets its own clipping cell.
    var cells: [Int: UIView] = [:]
    private var accentViews: [(view: UIImageView, accent: GiftMorphAccent)] = []
    private let bottom: GiftMorphBottom?

    init?(pair: GiftMorphPair, toStats: Bool, bottom: GiftMorphBottom?) {
        guard let anchor = pair.card ?? pair.stats else {
            return nil
        }
        self.bottom = pair.anchorsBottom ? bottom : nil
        self.anchor = anchor
        self.card = pair.card
        self.stats = pair.stats
        self.near = pair.near
        self.emerges = pair.emerges
        self.window = pair.window
        self.toStats = toStats
        self.hasCardSurface = pair.card.map { $0.hasSurface } ?? (pair.near != nil && !pair.emerges)
        self.hasStatsSurface = pair.stats.map { $0.hasSurface } ?? (pair.near != nil)
        self.growsOutOfNeighbour = pair.card == nil && pair.near != nil && !pair.emerges && !pair.fadesOut
        self.fillsInWindow = pair.fillsInWindow
        self.ridesBelow = pair.stats == nil && pair.near == nil ? pair.ridesBelow : nil
        self.goesOutInPlace = pair.stats == nil && pair.near == nil && pair.ridesBelow == nil
        self.comesInInPlace = pair.card == nil && pair.near == nil
        self.dissolves = pair.dissolves
        self.isBorn = pair.isBorn && pair.stats == nil
        if pair.dissolves, let card = pair.card?.look.frame, let stats = pair.stats?.look.frame, stats.width * stats.height > 0.0 {
            self.shrinks = card.width * card.height < stats.width * stats.height * GiftMorphTiming.shrinkRatio
        } else {
            self.shrinks = false
        }
        self.isQuick = pair.isQuick || self.shrinks
        self.mergesInto = pair.card == nil ? pair.mergesInto : nil
        self.fadesOutInPlace = pair.fadesOut
        self.cardThings = GiftMorphPiece.things(of: pair.card, dissolves: pair.dissolves)
        self.statsThings = GiftMorphPiece.things(of: pair.stats, dissolves: pair.dissolves)

        self.clip.isUserInteractionEnabled = false
        self.flatBody.isUserInteractionEnabled = false
        self.flatBody.layer.cornerCurve = .continuous
        self.flatBody.addSubview(self.flatRim)
        self.clip.clipsToBounds = true
        self.clip.layer.cornerCurve = .continuous
        for accent in pair.stats?.accents ?? [] {
            let view = UIImageView(image: accent.image)
            view.isUserInteractionEnabled = false
            view.alpha = 0.0
            view.layer.compositingFilter = accent.compositingFilter
            self.accentViews.append((view, accent))
        }
    }

    private static func things(of end: GiftMorphEnd?, dissolves: Bool) -> [GiftMorphThing] {
        let things = end?.things ?? []
        return dissolves ? things.map { $0.rigid() } : things
    }

    var target: GiftMorphEnd? {
        return self.toStats ? self.stats : self.card
    }

    func install(in overlay: UIView) {
        for item in self.accentViews where item.accent.isUnder {
            overlay.addSubview(item.view)
        }
        overlay.addSubview(self.flatBody)
        // Inside the body so the rim blends with the fill and is clipped to its shape (see apply).
        for item in self.accentViews where !item.accent.isUnder {
            self.flatBody.addSubview(item.view)
        }
        overlay.addSubview(self.clip)
        for thing in self.cardThings + self.statsThings {
            thing.activate()
            if case let .row(number) = thing.path {
                let cell = self.cells[number] ?? UIView()
                if cell.superview == nil {
                    cell.clipsToBounds = true
                    cell.isUserInteractionEnabled = false
                    self.cells[number] = cell
                    self.clip.addSubview(cell)
                }
                cell.addSubview(thing.view)
            } else {
                self.clip.addSubview(thing.view)
            }
        }
    }

    static func smooth(_ value: CGFloat) -> CGFloat {
        let t = min(1.0, max(0.0, value))
        return t * t * (3.0 - 2.0 * t)
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ p: CGFloat) -> CGFloat {
        return a + (b - a) * p
    }

    static func lerp(_ a: CGRect, _ b: CGRect, _ p: CGFloat) -> CGRect {
        return CGRect(x: self.lerp(a.minX, b.minX, p), y: self.lerp(a.minY, b.minY, p), width: self.lerp(a.width, b.width, p), height: self.lerp(a.height, b.height, p))
    }

    // A missing end is taken from the neighbour, or a thin strip on its bottom edge for an emerging surface.
    func looks() -> (card: GiftMorphLook, stats: GiftMorphLook) {
        if let card = self.card, let stats = self.stats {
            return (card.look, stats.look)
        }
        if let card = self.card {
            let look = card.look
            return (look, self.near?.look ?? look)
        }
        let look = self.anchor.look
        guard let near = self.near?.look else {
            return (look, look)
        }
        if self.mergesIntoTop {
            let top = CGRect(x: look.frame.minX, y: near.frame.minY, width: look.frame.width, height: 0.0)
            return (GiftMorphLook(frame: top, radius: 0.0, flat: near.flat), look)
        }
        if self.emerges {
            let thickness = GiftMorphPiece.thickness
            let strip = CGRect(x: look.frame.minX, y: near.frame.maxY - thickness, width: look.frame.width, height: thickness)
            return (GiftMorphLook(frame: strip, radius: thickness / 2.0, flat: look.flat), look)
        }
        return (near, look)
    }

    private func shape(of moment: GiftMorphMoment) -> CGFloat {
        let p = min(1.0, max(0.0, moment.position))
        guard self.isQuick else {
            return p
        }
        return 1.0 - GiftMorphPiece.smooth((1.0 - moment.time) / GiftMorphTiming.shrinkDone)
    }

    // overlay and card frames differ only for pieces in the bottom overlay, which does not move with the card.
    private func frames(p: CGFloat, q: CGFloat, a: GiftMorphLook, b: GiftMorphLook) -> (overlay: CGRect, card: CGRect) {
        var frame = GiftMorphPiece.lerp(a.frame, b.frame, q)
        if let panel = self.mergesInto, let tableTop = self.near?.look.frame.minY {
            // Height and gap to the panel's top edge shrink together, ending as a line on that edge.
            let panelTop = GiftMorphPiece.lerp(tableTop, panel.look.frame.minY, p)
            let distance = b.frame.maxY - panel.look.frame.minY
            let k = GiftMorphPiece.smooth(p)
            frame.size.height = b.frame.height * k
            frame.origin.y = panelTop + distance * k - frame.height
        }
        var card = frame
        if let bottom = self.bottom {
            let distance = GiftMorphPiece.lerp(bottom.cardHeight - a.frame.maxY, bottom.statsHeight - b.frame.maxY, q)
            frame.origin.y = bottom.endHeight - distance - frame.height
            card.origin.y = GiftMorphPiece.lerp(bottom.cardHeight, bottom.statsHeight, p) - distance - frame.height
        }
        return (frame, card)
    }

    func cardFrame(at moment: GiftMorphMoment) -> CGRect {
        let looks = self.looks()
        let frames = self.frames(p: min(1.0, max(0.0, moment.position)), q: self.shape(of: moment), a: looks.card, b: looks.stats)
        return self.riding(frames.card, at: moment)
    }

    // Offset of an edge from its place in the stats layout.
    func displacement(of ride: GiftMorphBlock.Ride, at moment: GiftMorphMoment) -> CGFloat {
        let now = self.cardFrame(at: moment)
        let own = self.looks().stats.frame
        switch ride {
        case .top:
            return now.minY - own.minY
        case .bottom:
            return now.maxY - own.maxY
        case .still:
            return 0.0
        }
    }

    private func goneShare(moment: GiftMorphMoment) -> CGFloat {
        return 1.0 - GiftMorphPiece.smooth(self.window.progress(at: moment.time))
    }

    // Geometry follows moment.position, content swaps follow moment.time.
    func apply(_ moment: GiftMorphMoment) {
        let looks = self.looks()
        let a = looks.card
        let b = looks.stats
        let p = min(1.0, max(0.0, moment.position))
        let q = self.shape(of: moment)
        let frame = self.riding(self.frames(p: p, q: q, a: a, b: b).overlay, at: moment)
        let radiusFrom = GiftMorphPiece.lerp(a.radius, b.radius, q)
        let radius = self.ridesBelow != nil ? 0.0 : min(min(frame.width, frame.height) / 2.0, max(0.0, (radiusFrom * 4.0).rounded() / 4.0))
        let gone = self.fadesOutInPlace ? self.goneShare(moment: moment) : 0.0

        var bodyAlpha: CGFloat = 1.0
        if self.growsOutOfNeighbour {
            bodyAlpha *= GiftMorphPiece.smooth(GiftMorphTiming.flatRise.progress(at: moment.time))
        }
        if !self.hasCardSurface {
            bodyAlpha *= GiftMorphPiece.smooth(q / GiftMorphPiece.surfaceWindow)
        }
        if !self.hasStatsSurface {
            bodyAlpha *= 1.0 - GiftMorphPiece.smooth((q - (1.0 - GiftMorphPiece.surfaceWindow)) / GiftMorphPiece.surfaceWindow)
        }
        if self.goesOutInPlace {
            bodyAlpha = 1.0 - GiftMorphPiece.smooth(p / GiftMorphPiece.swapOut)
        } else if self.comesInInPlace {
            bodyAlpha = GiftMorphPiece.smooth((p - GiftMorphPiece.swapIn) / (1.0 - GiftMorphPiece.swapIn))
        }
        if self.fadesOutInPlace {
            bodyAlpha = 1.0 - gone
        }
        if self.ridesBelow != nil {
            bodyAlpha = 0.0
        }

        let from = self.hasCardSurface ? a.flat : b.flat
        let to = self.hasStatsSurface ? b.flat : a.flat
        let share = self.fillsInWindow ? GiftMorphPiece.smooth(self.window.progress(at: moment.time)) : q
        let mixed = self.fadesOutInPlace ? b.flat : from.mixed(with: to, alpha: share)
        self.flatBody.backgroundColor = mixed.fill
        self.flatBody.frame = frame
        self.flatBody.layer.cornerRadius = radius
        self.flatBody.alpha = bodyAlpha
        self.flatRim.frame = CGRect(origin: .zero, size: frame.size)
        self.flatRim.update(size: frame.size, cornerRadius: radius, strength: mixed.rimStrength, transition: .immediate)
        self.clip.frame = frame
        self.clip.layer.cornerRadius = radius
        let settle = GiftMorphPiece.smooth(GiftMorphTiming.settle.progress(at: moment.time))
        // Clip the rim accent to the body; unclipped, its blend mode shows a halo outside the caps.
        self.flatBody.layer.masksToBounds = settle >= 0.001 && self.accentViews.contains(where: { !$0.accent.isUnder })
        for item in self.accentViews {
            item.view.isHidden = settle < 0.001
            let place = item.accent.isUnder ? frame : CGRect(origin: .zero, size: frame.size)
            item.view.frame = place.insetBy(dx: -item.accent.outset, dy: -item.accent.outset)
            item.view.alpha = item.accent.alpha * settle * (1.0 - gone)
        }
        self.layoutThings(frame: frame, a: a, b: b, p: q, time: moment.time, gone: gone)
    }

    func land() {
        guard !self.isLanded else {
            return
        }
        self.isLanded = true
        for thing in self.cardThings + self.statsThings {
            thing.view.transform = .identity
            thing.view.alpha = 1.0
            thing.view.removeFromSuperview()
            thing.release()
        }
        if let target = self.target {
            target.revealing()
            for view in target.reveal {
                view.layer.removeAllAnimations()
                view.alpha = 1.0
            }
        }
        for item in self.accentViews {
            item.view.removeFromSuperview()
        }
        self.flatBody.removeFromSuperview()
        self.clip.removeFromSuperview()
        self.onLanding?()
    }
}
