import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import AppBundle
import ContextUI
import UndoUI

/// Mini gift card that morphs out of the tapped row's model thumbnail and back on close.
/// Horizontal swipes page between gifts; swipe down, tap outside, close or "OK" dismiss it.
final class GiftSaleMiniCardController: ViewController {
    private let context: AccountContext
    private let entries: [GiftMiniCardEntry]
    private let firstIndex: Int
    private var index: Int
    private weak var sourceView: UIView?
    private let dim = UIView()
    private var card: GiftSaleMiniCardView?
    private var layout: ContainerViewLayout?
    private var isDismissing = false
    // Morph state: 0 is the row thumbnail, 1 is the card.
    private var link: CADisplayLink?
    private var morphValue: CGFloat = 0.0
    private var morphVelocity: CGFloat = 0.0
    private var morphTarget: CGFloat = 1.0
    private var morphSpring: (stiffness: CGFloat, damping: CGFloat) = (0.0, 0.0)
    private var morphSource: CGRect = .zero
    private var morphCard: CGRect = .zero
    private var morphCompletion: (() -> Void)?
    private var lastTick: CFTimeInterval = 0.0

    init(context: AccountContext, entries: [GiftMiniCardEntry], index: Int, source: UIView?) {
        self.context = context
        self.entries = entries
        self.firstIndex = index
        self.index = index
        self.sourceView = source
        super.init(navigationBarPresentationData: nil)
        self.statusBar.statusBarStyle = .Ignore
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.link?.invalidate()
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNodeDidLoad()
        self.dim.backgroundColor = UIColor(white: 0.0, alpha: 0.45)
        self.dim.alpha = 0.0
        self.dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dimTapped)))
        self.displayNode.view.addSubview(self.dim)
        self.displayNode.view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(self.panned(_:))))
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let isFirst = self.layout == nil
        self.layout = layout
        self.dim.frame = CGRect(origin: .zero, size: layout.size)
        if isFirst {
            let card = self.makeCard(index: self.index)
            self.card = card
            card.isHidden = true
            // Let the card render its content for a few frames before it grows out of the row.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.appear()
            }
        } else if let card = self.card, self.link == nil {
            card.center = self.restingCenter
        }
    }

    private var restingCenter: CGPoint {
        guard let layout = self.layout else {
            return .zero
        }
        return CGPoint(x: layout.size.width / 2.0, y: layout.size.height / 2.0)
    }

    /// Nil when the row is off screen.
    private func sourceFrame() -> CGRect? {
        guard let source = self.sourceView, source.window != nil else {
            return nil
        }
        return source.convert(source.bounds, to: self.displayNode.view)
    }

    private func restingFrame(of card: GiftSaleMiniCardView) -> CGRect {
        let size = card.root.bounds.size
        let center = self.restingCenter
        return CGRect(x: center.x - size.width / 2.0, y: center.y - size.height / 2.0, width: size.width, height: size.height)
    }

    private func appear() {
        guard let card = self.card, !self.isDismissing else {
            return
        }
        card.isHidden = false
        if UIAccessibility.isReduceMotionEnabled {
            card.settle()
            card.center = self.restingCenter
            card.alpha = 0.0
            card.transform = .identity
            UIView.animate(withDuration: 0.2, animations: {
                self.dim.alpha = 1.0
                card.alpha = 1.0
            })
            return
        }
        UIView.animate(withDuration: 0.3, delay: 0.0, options: [.curveEaseOut], animations: {
            self.dim.alpha = 1.0
        })
        guard let source = self.sourceFrame() else {
            card.settle()
            card.center = self.restingCenter
            card.alpha = 0.0
            card.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            UIView.animate(withDuration: 0.45, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.0, options: [], animations: {
                card.alpha = 1.0
                card.transform = .identity
            })
            return
        }
        self.sourceView?.alpha = 0.0
        self.morphSource = source
        self.morphCard = self.restingFrame(of: card)
        self.runMorph(from: 0.0, to: 1.0, response: 0.52, damping: 0.8, completion: { [weak self] in
            self?.card?.settle()
            if let self, let card = self.card {
                card.center = self.restingCenter
            }
        })
    }

    private func runMorph(from: CGFloat, to: CGFloat, response: CGFloat, damping: CGFloat, completion: @escaping () -> Void) {
        self.morphValue = from
        self.morphVelocity = 0.0
        self.morphTarget = to
        let omega = 2.0 * CGFloat.pi / response
        self.morphSpring = (omega * omega, 2.0 * damping * omega)
        self.morphCompletion = completion
        self.applyMorph()
        self.link?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(self.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        self.lastTick = CACurrentMediaTime()
    }

    private func applyMorph() {
        guard let card = self.card else {
            return
        }
        // The row may have scrolled meanwhile; track its current position.
        if self.isDismissing, let live = self.sourceFrame() {
            self.morphSource = live
        }
        let source = self.morphSource
        card.applyMorph(p: self.morphValue, source: source, target: self.morphCard, sourceRadius: source.width * 0.26)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        var remaining = min(0.05, now - self.lastTick)
        self.lastTick = now
        // Substeps keep the spring stable.
        while remaining > 0.0 {
            let dt = CGFloat(min(remaining, 1.0 / 240.0))
            let force = -self.morphSpring.stiffness * (self.morphValue - self.morphTarget) - self.morphSpring.damping * self.morphVelocity
            self.morphVelocity += force * dt
            self.morphValue += self.morphVelocity * dt
            remaining -= Double(dt)
        }
        let isDone = abs(self.morphValue - self.morphTarget) < 0.0015 && abs(self.morphVelocity) < 0.02
        if isDone {
            self.morphValue = self.morphTarget
        }
        self.applyMorph()
        if isDone {
            self.stopMorph()
        }
    }

    private func stopMorph() {
        self.link?.invalidate()
        self.link = nil
        let completion = self.morphCompletion
        self.morphCompletion = nil
        completion?()
    }

    private func makeCard(index: Int) -> GiftSaleMiniCardView {
        let width = min(340.0, (self.layout?.size.width ?? 375.0) - 48.0)
        let gift = self.entries[index].gift
        let card = GiftSaleMiniCardView(context: self.context, entry: self.entries[index], width: width, close: { [weak self] in
            self?.close()
        }, more: { [weak self] sourceView in
            self?.openMore(gift: gift, sourceView: sourceView)
        })
        card.center = self.restingCenter
        self.displayNode.view.addSubview(card)
        return card
    }

    private func openMore(gift: StarGift.UniqueGift, sourceView: UIView) {
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        let link = "https://t.me/nft/\(gift.slug)"
        let items: [ContextMenuItem] = [
            .action(ContextMenuActionItem(text: presentationData.strings.Gift_View_Context_CopyLink, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Link"), color: theme.contextMenu.primaryColor)
            }, action: { [weak self] c, _ in
                c?.dismiss(completion: nil)
                UIPasteboard.general.string = link
                self?.present(UndoOverlayController(presentationData: presentationData, content: .linkCopied(title: nil, text: presentationData.strings.Conversation_LinkCopied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), in: .window(.root))
            }))
        ]
        let contextController = makeContextController(presentationData: presentationData, source: .reference(GiftMiniCardReferenceSource(controller: self, sourceView: sourceView)), items: .single(ContextController.Items(content: .list(items))), gesture: nil)
        self.presentInGlobalOverlay(contextController)
    }

    @objc private func dimTapped() {
        self.close()
    }

    private func neighbour(_ step: Int) -> Int? {
        let i = self.index + step
        return i >= 0 && i < self.entries.count ? i : nil
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        guard let card = self.card, let layout = self.layout, !self.isDismissing else {
            return
        }
        let translation = pan.translation(in: self.displayNode.view)
        let velocity = pan.velocity(in: self.displayNode.view)
        let center = self.restingCenter
        switch pan.state {
        case .began:
            if self.link != nil {
                self.link?.invalidate()
                self.link = nil
                self.morphCompletion = nil
                card.settle()
                card.center = center
            }
            card.alpha = 1.0
        case .changed:
            if abs(translation.x) >= abs(translation.y) {
                // Rubber-band past the first or last gift.
                let step = translation.x < 0.0 ? 1 : -1
                let x = self.neighbour(step) == nil ? translation.x * 0.25 : translation.x
                card.center = CGPoint(x: center.x + x, y: center.y)
                card.transform = CGAffineTransform(rotationAngle: x / layout.size.width * 0.12)
            } else {
                let y = max(0.0, translation.y)
                card.center = CGPoint(x: center.x, y: center.y + y)
                card.transform = .identity
                self.dim.alpha = 1.0 - min(1.0, y / 400.0)
            }
        case .ended, .cancelled:
            if abs(translation.x) >= abs(translation.y) {
                let step = translation.x < 0.0 ? 1 : -1
                if let next = self.neighbour(step), abs(translation.x) > 70.0 || abs(velocity.x) > 500.0 {
                    self.flip(to: next, direction: CGFloat(step))
                    return
                }
            } else if translation.y > 110.0 || velocity.y > 800.0 {
                self.close()
                return
            }
            let animator = UIViewPropertyAnimator(duration: 0.45, dampingRatio: 0.8) {
                card.center = center
                card.transform = .identity
                self.dim.alpha = 1.0
            }
            animator.startAnimation()
        default:
            break
        }
    }

    private func flip(to index: Int, direction: CGFloat) {
        guard let old = self.card, let layout = self.layout else {
            return
        }
        self.index = index
        let card = self.makeCard(index: index)
        self.card = card
        let center = self.restingCenter
        let distance = layout.size.width * 0.9
        card.center = CGPoint(x: center.x + direction * distance, y: center.y)
        card.transform = CGAffineTransform(rotationAngle: direction * 0.08)
        let animator = UIViewPropertyAnimator(duration: 0.5, dampingRatio: 0.84) {
            old.center = CGPoint(x: center.x - direction * distance, y: center.y)
            old.transform = CGAffineTransform(rotationAngle: -direction * 0.08)
            old.alpha = 0.0
            card.center = center
            card.transform = .identity
        }
        animator.addCompletion { _ in
            old.removeFromSuperview()
        }
        animator.startAnimation()
    }

    /// Morphs back into the source row if it is visible and still shows the same gift; otherwise shrinks and fades in place.
    private func close() {
        guard !self.isDismissing else {
            return
        }
        self.isDismissing = true
        self.displayNode.view.isUserInteractionEnabled = false
        guard let card = self.card else {
            self.finishDismiss()
            return
        }
        let wasMorphing = self.link != nil
        self.link?.invalidate()
        self.link = nil
        self.morphCompletion = nil
        if UIAccessibility.isReduceMotionEnabled {
            self.sourceView?.alpha = 1.0
            UIView.animate(withDuration: 0.2, animations: {
                self.dim.alpha = 0.0
                card.alpha = 0.0
            }, completion: { [weak self] _ in
                self?.finishDismiss()
            })
            return
        }
        UIView.animate(withDuration: 0.3, delay: 0.0, options: [.curveEaseInOut], animations: {
            self.dim.alpha = 0.0
        })
        if self.index == self.firstIndex, let source = self.sourceFrame() {
            // Start from the current frame; the card may have been pulled down.
            if !wasMorphing {
                card.transform = .identity
                card.settle()
                let center = card.center
                let size = card.root.bounds.size
                self.morphCard = CGRect(x: center.x - size.width / 2.0, y: center.y - size.height / 2.0, width: size.width, height: size.height)
                self.morphValue = 1.0
            }
            self.morphSource = source
            let start = self.morphValue
            self.runMorph(from: start, to: 0.0, response: 0.42, damping: 1.0, completion: { [weak self] in
                guard let self else {
                    return
                }
                self.finishInRow()
            })
            return
        }
        self.sourceView?.alpha = 1.0
        let animator = UIViewPropertyAnimator(duration: 0.3, dampingRatio: 1.0) {
            card.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            card.alpha = 0.0
        }
        animator.addCompletion { [weak self] _ in
            self?.finishDismiss()
        }
        animator.startAnimation()
    }

    /// The shrunk card is reparented over the row thumbnail so it scrolls with the row and doesn't block the stats
    /// while the sticker finishes its loop, then the row shows its own thumbnail again.
    private func finishInRow() {
        guard let card = self.card else {
            self.sourceView?.alpha = 1.0
            self.finishDismiss()
            return
        }
        let source = self.sourceView
        if let source, let holder = source.superview, source.window != nil, let superview = card.superview {
            let center = superview.convert(card.center, to: holder)
            card.removeFromSuperview()
            card.center = center
            card.isUserInteractionEnabled = false
            holder.insertSubview(card, aboveSubview: source)
        } else {
            source?.alpha = 1.0
            card.removeFromSuperview()
            self.finishDismiss()
            return
        }
        self.finishDismiss()
        card.finishAnimation(maximumDuration: GiftSaleMiniCardController.finishLimit, completion: { [weak card, weak source] in
            source?.alpha = 1.0
            card?.removeFromSuperview()
        })
    }

    private static let finishLimit: Double = 1.0

    private func finishDismiss() {
        if GiftStatsSaleOpening.presented === self {
            GiftStatsSaleOpening.presented = nil
        }
        self.presentingViewController?.dismiss(animated: false, completion: nil)
        self.dismiss()
    }
}

private final class GiftMiniCardReferenceSource: ContextReferenceContentSource {
    private let controller: ViewController
    private let sourceView: UIView

    init(controller: ViewController, sourceView: UIView) {
        self.controller = controller
        self.sourceView = sourceView
    }

    func transitionInfo() -> ContextControllerReferenceViewInfo? {
        return ContextControllerReferenceViewInfo(referenceView: self.sourceView, contentAreaInScreenSpace: UIScreen.main.bounds)
    }
}
