import Foundation
import UIKit
import Display
import MultilineTextComponent
import GiftAnimationComponent
import GiftStatsScreen
import GiftStats

/// Footer views of the gift card.
struct GiftViewStatsFooter {
    var button: [UIView]
    var fade: UIView?
}

/// Identifies and captures card subviews as morph transition endpoints (`GiftMorphEnd`).
final class GiftViewStatsParts {
    private(set) var gift: GiftCompositionComponent.View?
    private(set) var backdrop: GiftViewFullBackdropComponent.View?
    private(set) var buttons: [GiftMorphEnd] = []
    private(set) var table: GiftMorphEnd?
    private(set) var footerText: GiftMorphEnd?
    private(set) var footer: GiftMorphEnd?
    private weak var card: UIView?
    private(set) var corners: [GiftMorphEnd] = []
    private(set) var title: UIView?
    private(set) var titlePicture: UIView?
    private(set) var titleFrame: CGRect = .zero
    private let palette: GiftTonalPalette
    private(set) var others: [UIView] = []
    private(set) var fade: UIView?
    private var hidden: [UIView] = []

    init(card: UIView, content: UIView, controlPanel: UIView?, footer: GiftViewStatsFooter, valueRow: UIView?, palette: GiftTonalPalette) {
        self.palette = palette
        self.card = card
        var table: UIView?
        var tableFrame: CGRect?
        if let candidate = valueRow?.superview, candidate.superview === content {
            table = candidate
            tableFrame = candidate.frame
        }
        var cluster: [UIView] = []
        var singles: [UIView] = []
        var buttonViews: [UIView] = []
        for view in content.subviews {
            if view is GiftCompositionComponent.View {
                self.gift = view as? GiftCompositionComponent.View
                continue
            }
            if view is GiftViewFullBackdropComponent.View {
                self.backdrop = view as? GiftViewFullBackdropComponent.View
                continue
            }
            if view is GiftViewHeaderFadeComponent.View || view.isHidden || view.alpha < 0.01 || view.bounds.isEmpty {
                continue
            }
            if let tableFrame, GiftViewStatsParts.same(view.frame, tableFrame) {
                cluster.append(view)
            } else if view is HeaderButtonComponent.View {
                buttonViews.append(view)
            } else {
                singles.append(view)
            }
        }
        buttonViews.sort { $0.frame.minX < $1.frame.minX }
        self.buttons = buttonViews.compactMap { self.buttonEnd($0, card: card) }
        if let table, !cluster.isEmpty {
            self.table = self.tableEnd(table: table, cluster: cluster, card: card)
        } else {
            singles.append(contentsOf: cluster)
        }
        // First text under the gift is the title.
        let texts = singles.filter { $0 is MultilineTextComponent.View }.sorted { $0.frame.minY < $1.frame.minY }
        if let tableFrame, let line = texts.first(where: { $0.frame.minY >= tableFrame.maxY - 2.0 }) {
            self.footerText = self.footerTextEnd(line, card: card)
            singles.removeAll { $0 === line }
        }
        if let gift = self.gift, let title = texts.first(where: { $0.frame.minY > gift.frame.midY && $0 !== self.footerText?.reveal.first }) {
            self.title = title
            self.titleFrame = title.convert(title.bounds, to: card)
            singles.removeAll { $0 === title }
        }
        self.others = singles
        if let controlPanel, !controlPanel.isHidden {
            self.corners = self.cornerEnds(controlPanel, card: card)
        }
        if !footer.button.isEmpty {
            self.footer = self.footerEnd(footer, card: card)
            self.fade = footer.fade
        }
    }

    private static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        return abs(a.minX - b.minX) < 1.0 && abs(a.minY - b.minY) < 1.0 && abs(a.width - b.width) < 1.0 && abs(a.height - b.height) < 1.0
    }

    /// Captures snapshots and frames before statistics layout.
    func freeze() {
        for end in self.allEnds {
            end.capture(isFrozen: true)
        }
        if let title = self.title {
            self.titlePicture = GiftMorphCapture.picture(of: title)
        }
    }

    var allEnds: [GiftMorphEnd] {
        return self.buttons + self.corners + [self.table, self.footerText, self.footer].compactMap { $0 }
    }

    var allViews: [UIView] {
        return self.allEnds.flatMap { $0.reveal } + self.others + (self.title.map { [$0] } ?? []) + (self.fade.map { [$0] } ?? [])
    }

    // MARK: Ends

    private func hide(_ views: [UIView]) -> () -> Void {
        return { [weak self] in
            self?.keepHidden(views)
        }
    }

    private func release(_ views: [UIView]) -> () -> Void {
        return { [weak self] in
            self?.hidden.removeAll { hiddenView in
                views.contains(where: { $0 === hiddenView })
            }
        }
    }

    func keepHidden(_ views: [UIView]) {
        for view in views where !self.hidden.contains(where: { $0 === view }) {
            self.hidden.append(view)
        }
        self.reapply()
    }

    func letGo(_ views: [UIView]) {
        self.release(views)()
    }

    private static let gone = GiftMorphLook(frame: .zero, radius: 0.0, flat: .control)

    private func buttonEnd(_ view: UIView, card: UIView) -> GiftMorphEnd? {
        guard let flat = GiftMorphCapture.allFlat(in: view).first else {
            return nil
        }
        return self.flatEnd(flat, reveal: [view], card: card)
    }

    private func flatEnd(_ flat: GiftFlatTonalView, reveal: [UIView], card: UIView) -> GiftMorphEnd {
        return GiftMorphEnd(
            reveal: reveal,
            look: { [weak flat, weak card] in
                guard let flat, let card else {
                    return GiftViewStatsParts.gone
                }
                return flat.morphLook(in: card)
            },
            things: { [weak flat, weak card] isFrozen in
                guard let flat, let card else {
                    return []
                }
                return GiftMorphCapture.picture(onFlat: flat, in: card, isFrozen: isFrozen).map { [$0] } ?? []
            },
            hide: self.hide(reveal),
            revealing: self.release(reveal)
        )
    }

    private func tableEnd(table: UIView, cluster: [UIView], card: UIView) -> GiftMorphEnd {
        let panel = self.palette.table.panel
        return GiftMorphEnd(
            reveal: cluster,
            look: { [weak table, weak card] in
                guard let table, let card else {
                    return GiftViewStatsParts.gone
                }
                return GiftMorphLook(frame: table.convert(table.bounds, to: card), radius: GiftTonalPalette.cornerRadius, flat: GiftFlat(fill: panel, border: nil))
            },
            things: { [weak table, weak card] isFrozen in
                guard let table, let card else {
                    return []
                }
                return GiftMorphCapture.rows(of: table, in: card, skipping: nil, isFrozen: isFrozen)
            },
            hide: self.hide(cluster),
            revealing: self.release(cluster)
        )
    }

    private func footerTextEnd(_ line: UIView, card: UIView) -> GiftMorphEnd {
        return GiftMorphEnd(
            reveal: [line],
            hasSurface: false,
            look: { [weak line, weak card] in
                guard let line, let card else {
                    return GiftViewStatsParts.gone
                }
                let frame = line.convert(line.bounds, to: card)
                return GiftMorphLook(frame: frame, radius: frame.height / 2.0, flat: .control)
            },
            things: { [weak line, weak card] isFrozen in
                guard let line, let card, let picture = GiftMorphCapture.picture(of: line) else {
                    return []
                }
                let frame = line.convert(line.bounds, to: card)
                return [isFrozen ? GiftMorphThing(picture: picture, frame: frame) : GiftMorphThing(view: picture, home: { [weak line, weak card] in
                    guard let line, let card else {
                        return frame
                    }
                    return line.convert(line.bounds, to: card)
                })]
            },
            hide: self.hide([line]),
            revealing: self.release([line])
        )
    }

    private func footerEnd(_ footer: GiftViewStatsFooter, card: UIView) -> GiftMorphEnd {
        let surface = footer.button.first(where: { $0 is GiftFlatTonalView })
        let label = footer.button.first(where: { !($0 is GiftFlatTonalView) })
        return GiftMorphEnd(
            reveal: footer.button,
            look: { [weak surface, weak card] in
                guard let card else {
                    return GiftViewStatsParts.gone
                }
                let frame = (surface ?? card).convert((surface ?? card).bounds, to: card)
                let fill = (surface as? GiftFlatTonalView)?.flat ?? .control
                return GiftMorphLook(frame: frame, radius: frame.height / 2.0, flat: fill)
            },
            things: { [weak label, weak card] isFrozen in
                guard let card, let label else {
                    return []
                }
                GiftMorphCapture.removeAnimations(in: label)
                guard let picture = GiftMorphCapture.picture(of: label) else {
                    return []
                }
                let frame = label.convert(label.bounds, to: card)
                return [isFrozen ? GiftMorphThing(picture: picture, frame: frame) : GiftMorphThing(view: picture, home: { [weak label, weak card] in
                    guard let label, let card else {
                        return frame
                    }
                    return label.convert(label.bounds, to: card)
                })]
            },
            hide: self.hide(footer.button),
            revealing: self.release(footer.button)
        )
    }

    private func cornerEnds(_ panel: UIView, card: UIView) -> [GiftMorphEnd] {
        let list = GiftMorphCapture.allFlat(in: panel).sorted { $0.convert($0.bounds, to: card).minX < $1.convert($1.bounds, to: card).minX }
        return list.map { self.flatEnd($0, reveal: [panel], card: card) }
    }

    // MARK: Hiding

    /// Keeps the views that are taken off invisible: the card lays itself out again at times and sets them back.
    func reapply() {
        for view in self.hidden {
            GiftMorphCapture.removeAnimations(in: view)
            view.alpha = 0.0
        }
    }

    /// The views are let go of: they are made visible by whoever brings them back.
    func releaseAll() {
        self.hidden.removeAll()
    }

    /// The card as the card, at once, wherever the morph was: everything that was taken off is back and the gift and the backdrop are as they were (the card is
    /// going away, or the morph has been stopped).
    func restoreCard() {
        self.releaseAll()
        for view in self.allViews {
            view.layer.removeAllAnimations()
            view.alpha = 1.0
        }
        self.setAccessibilityHidden(false)
        self.gift?.transform = .identity
        self.moveSymbols(for: .identity)
        self.setSymbolsFlow(nil)
        self.setCraftLevel(0.0)
        self.setCraftShift(0.0)
    }

    /// The views of the card that the statistics take over are out of sight; a screen reader must not read them either (`hidden`), and reads them again when they
    /// are back.
    func setAccessibilityHidden(_ hidden: Bool) {
        for view in self.allViews {
            view.accessibilityElementsHidden = hidden
        }
    }

    /// Takes every view that the morph takes off out of sight at once (with Reduce Motion).
    func hideAll() {
        for end in self.allEnds {
            end.hide()
        }
        self.keepHidden(self.others + (self.title.map { [$0] } ?? []) + (self.fade.map { [$0] } ?? []))
    }

    // MARK: The gift

    /// The anchor of the gift: where its model is in the card and where it goes in the statistics (the gift is scaled about its middle).
    func giftTransform() -> CGAffineTransform {
        guard let gift = self.gift else {
            return .identity
        }
        let scale = GiftStatsHeaderMetrics.giftScale
        let shift = (GiftStatsHeaderMetrics.giftCenterY - gift.bounds.midY) - scale * (GiftStatsHeaderMetrics.headerMidY - gift.bounds.midY)
        return CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: 0.0, y: shift))
    }

    /// How far the model moves up or down when the gift gets `transform` (about its middle): the symbols are carried by the same distance.
    func symbolsShift(for transform: CGAffineTransform) -> CGFloat {
        guard let gift = self.gift else {
            return 0.0
        }
        let modelY = GiftViewFullBackdropComponent.modelCenterY
        return (gift.bounds.midY + (modelY - gift.bounds.midY) * transform.d + transform.ty) - modelY
    }

    /// The symbols follow the gift (call it in the animation of the gift, with the same transform).
    func moveSymbols(for transform: CGAffineTransform) {
        self.backdrop?.setSymbolsShift(self.symbolsShift(for: transform))
    }

    /// The Craft background is carried `dy` (see `GiftViewFullBackdropComponent.View.setCraftShift`).
    func setCraftShift(_ dy: CGFloat) {
        self.backdrop?.setCraftShift(dy)
    }

    /// How far the backdrop of the card is painted with the background of the Craft Gift screen (see `GiftViewFullBackdropComponent.View.setCraftLevel`).
    func setCraftLevel(_ level: CGFloat, symbolsFlow: Bool = false) {
        self.backdrop?.setCraftLevel(level, symbolsFlow: symbolsFlow)
    }

    /// The symbols of the backdrop flow into the gift (see `GiftSymbolFieldView.setFlow`); nil puts them back at their places.
    func setSymbolsFlow(_ progress: CGFloat?) {
        self.backdrop?.setSymbolsFlow(progress)
    }
}
