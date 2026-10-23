import Foundation
import UIKit
import Display
import ComponentFlow
import GiftStats

// Card <-> stats morph. Each pair is one GiftMorphPiece; everything is driven by the card's own height animation
// (GiftMorphClock), so the way back is the way there reversed. The overlay exists only while running.
public final class GiftMorph {
    // Safety limit, scaled for Slow Animations.
    private static var limit: Double {
        return 3.0 * max(1.0, UIView.animationDurationFactor)
    }

    private let host: UIView
    private let overlay = UIView()
    // Lives in the window, for pieces pinned to the card's bottom edge (GiftMorphPair.anchorsBottom).
    private let bottomOverlay = UIView()
    private var pieces: [GiftMorphPiece] = []
    private var blocks: [GiftMorphBlock] = []
    private var extras: [GiftMorphExtra] = []
    private var anchorPiece: GiftMorphPiece?
    private var piecesByEnd: [ObjectIdentifier: GiftMorphPiece] = [:]
    private var toStats = true
    private var link: CADisplayLink?
    private var clock: GiftMorphClock?
    private var driver: ((GiftMorphMoment) -> Void)?
    private var startTime = 0.0
    private var completion: (() -> Void)?

    public private(set) var isRunning = false
    private var settledFrames = 0

    public init(host: UIView) {
        self.host = host
    }

    // Source ends must be captured (GiftMorphEnd.capture) before the card is relaid out; startHeight is the height before that.
    public func run(pairs: [GiftMorphPair], blocks: [GiftMorphBlock], extras: [GiftMorphExtra] = [], toStats: Bool, startHeight: CGFloat, driver: @escaping (GiftMorphMoment) -> Void, completion: @escaping () -> Void) {
        guard !self.isRunning else {
            return
        }
        self.isRunning = true
        self.toStats = toStats
        self.blocks = blocks
        self.driver = driver
        self.completion = completion
        self.clock = GiftMorphClock(host: self.host, startHeight: startHeight, toStats: toStats)
        self.overlay.isUserInteractionEnabled = false
        self.overlay.frame = self.host.bounds
        self.host.addSubview(self.overlay)
        var bottom: GiftMorphBottom?
        if pairs.contains(where: { $0.anchorsBottom }), let window = self.host.window {
            let endHeight = self.host.bounds.height
            bottom = GiftMorphBottom(cardHeight: toStats ? startHeight : endHeight, statsHeight: toStats ? endHeight : startHeight, endHeight: endHeight)
            self.bottomOverlay.isUserInteractionEnabled = false
            self.bottomOverlay.frame = self.host.convert(self.host.bounds, to: window)
            window.addSubview(self.bottomOverlay)
        }

        var ends: [GiftMorphEnd] = []
        for pair in pairs {
            for end in [pair.card, pair.stats, pair.near].compactMap({ $0 }) where !end.isCaptured && !ends.contains(where: { $0 === end }) {
                ends.append(end)
            }
        }
        let shown = ends.flatMap { $0.reveal }
        GiftMorphCapture.withShown(shown) {
            for end in ends {
                end.capture(isFrozen: false)
            }
        }

        // Derived pieces go below the ones they grow out of.
        let isDerived: (GiftMorphPair) -> Bool = { $0.near != nil && ($0.card == nil || $0.stats == nil) }
        let ordered = pairs.filter(isDerived) + pairs.filter { !isDerived($0) }
        for pair in ordered {
            let source = toStats ? pair.card : pair.stats
            let target = toStats ? pair.stats : pair.card
            source?.hide()
            guard let piece = GiftMorphPiece(pair: pair, toStats: toStats, bottom: bottom) else {
                target?.revealing()
                for view in target?.reveal ?? [] {
                    view.layer.removeAllAnimations()
                    view.alpha = 1.0
                }
                continue
            }
            for view in target?.reveal ?? [] {
                view.layer.removeAllAnimations()
                view.alpha = 0.0
            }
            if pair.isAnchor {
                self.anchorPiece = piece
            }
            if let stats = pair.stats {
                self.piecesByEnd[ObjectIdentifier(stats)] = piece
            }
            piece.install(in: pair.anchorsBottom && bottom != nil ? self.bottomOverlay : self.overlay)
            self.pieces.append(piece)
        }
        for piece in self.pieces {
            if let end = piece.ridesBelow {
                piece.edgeHost = self.piecesByEnd[ObjectIdentifier(end)]
            }
        }
        for view in blocks.flatMap({ $0.views }) {
            view.layer.removeAllAnimations()
        }
        self.extras = extras
        for extra in extras {
            extra.install(in: self.overlay)
        }
        let start: CGFloat = toStats ? 0.0 : 1.0
        self.apply(GiftMorphMoment(position: start, time: start))
        let link = CADisplayLink(target: self, selector: #selector(self.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        self.startTime = CACurrentMediaTime()
    }

    private static func smooth(_ value: CGFloat) -> CGFloat {
        let t = min(1.0, max(0.0, value))
        return t * t * (3.0 - 2.0 * t)
    }

    // A block keeps its distance to the edge of the piece it rides; its own place is at progress 1.
    private func offset(of block: GiftMorphBlock, moment: GiftMorphMoment) -> CGFloat {
        let piece = block.panel.flatMap { self.piecesByEnd[ObjectIdentifier($0)] } ?? self.anchorPiece
        return piece?.displacement(of: block.ride, at: moment) ?? 0.0
    }

    private func apply(_ moment: GiftMorphMoment) {
        self.overlay.frame = self.host.bounds
        self.driver?(moment)
        for piece in self.pieces {
            piece.apply(moment)
        }
        for extra in self.extras {
            extra.apply(moment)
        }
        for block in self.blocks {
            let alpha = GiftMorph.smooth(block.window.progress(at: moment.time))
            let shift = self.offset(of: block, moment: moment)
            for view in block.views {
                view.alpha = alpha
                view.transform = CGAffineTransform(translationX: 0.0, y: shift)
            }
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let elapsed = now - self.startTime
        guard let clock = self.clock else {
            return
        }
        if self.host.window == nil {
            self.finish()
            return
        }
        // Place pieces where the card will be when this frame is shown (the simulator fires at targetTimestamp).
        let display = max(now, link.targetTimestamp) + GiftMorphClock.commitDelay
        let moment = clock.step(elapsed: elapsed, now: now, displayTime: display)
        if elapsed > GiftMorph.limit {
            self.finish()
            return
        }
        guard clock.isSettled else {
            self.apply(moment)
            return
        }
        // Hold one extra frame at the exact end; the last eased frame can be ~0.3 pt off and the swap would show a step.
        let end: CGFloat = self.toStats ? 1.0 : 0.0
        self.apply(GiftMorphMoment(position: end, time: end))
        self.settledFrames += 1
        if self.settledFrames >= 2 {
            self.finish()
        }
    }

    // Restores the real views without calling completion.
    public func cancel() {
        guard self.isRunning else {
            return
        }
        self.link?.invalidate()
        self.link = nil
        for piece in self.pieces {
            piece.onLanding = nil
            piece.land()
        }
        self.pieces = []
        for extra in self.extras {
            extra.land(toStats: self.toStats)
        }
        self.extras = []
        for block in self.blocks {
            for view in block.views {
                view.layer.removeAllAnimations()
                view.transform = .identity
            }
        }
        self.overlay.removeFromSuperview()
        self.bottomOverlay.removeFromSuperview()
        self.isRunning = false
        self.completion = nil
        self.driver = nil
    }

    private func finish() {
        self.link?.invalidate()
        self.link = nil
        let end: CGFloat = self.toStats ? 1.0 : 0.0
        self.driver?(GiftMorphMoment(position: end, time: end))
        for piece in self.pieces {
            piece.land()
        }
        self.pieces = []
        for extra in self.extras {
            extra.land(toStats: self.toStats)
        }
        self.extras = []
        for block in self.blocks {
            for view in block.views {
                view.layer.removeAllAnimations()
                view.alpha = self.toStats ? 1.0 : 0.0
                view.transform = .identity
            }
        }
        self.overlay.removeFromSuperview()
        self.bottomOverlay.removeFromSuperview()
        self.isRunning = false
        let completion = self.completion
        self.completion = nil
        self.driver = nil
        completion?()
    }
}
