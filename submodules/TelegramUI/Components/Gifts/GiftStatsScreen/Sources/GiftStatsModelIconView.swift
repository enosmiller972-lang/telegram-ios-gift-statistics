import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import AnimationCache
import MultiAnimationRenderer
import EmojiTextAttachmentView
import GiftStats
import ComponentFlow
import PeerInfoCoverComponent

private final class GiftStatsModelIconTarget: MultiAnimationRenderTarget {
    override func transitionToContents(_ contents: AnyObject, didLoop: Bool) {
        self.contents = contents
    }
}

/// First frame of a model sticker, optionally on a rounded square of its backdrop.
final class GiftStatsModelIconView: UIView {
    /// Fractions of the side.
    private static let cornerShare: CGFloat = 0.26
    private static let modelShare: CGFloat = 0.80
    private let backdropLayer = CAGradientLayer()
    private var backdrop: GiftSaleBackdrop?
    /// The card cover cropped exactly as `GiftSaleMiniCardView` shows it, so the card can shrink into the icon seamlessly.
    private let coverHost = UIView()
    private let cover = ComponentView<Empty>()
    private var coverGift: StarGift.UniqueGift?

    /// Geometry of the mini card (`GiftCompositionComponent` with the mini card's offset and scale).
    public static let cardWidth: CGFloat = 340.0
    private static let coverHeight: CGFloat = 520.0
    private static let coverCenter = CGPoint(x: 170.0, y: 67.0)
    public static let cardModelCenterY: CGFloat = 82.0
    public static let cardModelSide: CGFloat = 136.0 * 0.9
    private let target = GiftStatsModelIconTarget()
    private var fileId: Int64?
    private var disposable: Disposable?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.backdropLayer.type = .radial
        self.backdropLayer.startPoint = CGPoint(x: 0.5, y: 0.45)
        self.backdropLayer.endPoint = CGPoint(x: 1.15, y: 1.1)
        self.backdropLayer.cornerCurve = .continuous
        self.backdropLayer.masksToBounds = true
        self.backdropLayer.isHidden = true
        self.layer.addSublayer(self.backdropLayer)
        self.coverHost.isUserInteractionEnabled = false
        self.coverHost.clipsToBounds = true
        self.coverHost.layer.cornerCurve = .continuous
        self.coverHost.isHidden = true
        self.insertSubview(self.coverHost, at: 0)
        self.layer.addSublayer(self.target)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.disposable?.dispose()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.backdropLayer.frame = self.bounds
        self.backdropLayer.cornerRadius = self.bounds.width * GiftStatsModelIconView.cornerShare
        self.coverHost.frame = self.bounds
        self.coverHost.layer.cornerRadius = self.bounds.width * GiftStatsModelIconView.cornerShare
        if let view = self.cover.view {
            // Scale the cover so the card's model matches the icon's model, centred.
            let scale = self.bounds.width * GiftStatsModelIconView.modelShare / GiftStatsModelIconView.cardModelSide
            view.bounds = CGRect(origin: .zero, size: CGSize(width: GiftStatsModelIconView.cardWidth, height: GiftStatsModelIconView.coverHeight))
            view.transform = CGAffineTransform(scaleX: scale, y: scale)
            view.center = CGPoint(
                x: self.bounds.midX,
                y: self.bounds.midY + (GiftStatsModelIconView.coverHeight / 2.0 - GiftStatsModelIconView.cardModelCenterY) * scale
            )
        }
        if self.backdrop != nil || self.coverGift != nil {
            let side = self.bounds.width * GiftStatsModelIconView.modelShare
            self.target.frame = CGRect(x: (self.bounds.width - side) / 2.0, y: (self.bounds.height - side) / 2.0, width: side, height: side)
        } else {
            self.target.frame = self.bounds
        }
        CATransaction.commit()
    }

    /// With `gift` the full card cover is shown; otherwise `backdrop` colours only, or just the model.
    func update(context: AccountContext, file: TelegramMediaFile?, backdrop: GiftSaleBackdrop?, gift: StarGift.UniqueGift? = nil) {
        if self.coverGift?.id != gift?.id || (gift != nil && self.coverGift == nil) {
            self.coverGift = gift
            self.updateCover(context: context, gift: gift)
        }
        let backdrop = gift == nil ? backdrop : nil
        if self.backdrop != backdrop {
            self.backdrop = backdrop
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let backdrop {
                self.backdropLayer.colors = [UIColor(rgb: UInt32(bitPattern: backdrop.innerColor)).cgColor, UIColor(rgb: UInt32(bitPattern: backdrop.outerColor)).cgColor]
                self.backdropLayer.isHidden = false
            } else {
                self.backdropLayer.isHidden = true
            }
            CATransaction.commit()
            self.setNeedsLayout()
        }
        self.update(context: context, file: file)
    }

    private func updateCover(context: AccountContext, gift: StarGift.UniqueGift?) {
        var colors: (UIColor, UIColor, UIColor)?
        var patternFile: TelegramMediaFile?
        for attribute in gift?.attributes ?? [] {
            if case let .backdrop(_, _, innerColor, outerColor, patternColor, _, _) = attribute {
                colors = (UIColor(rgb: UInt32(bitPattern: outerColor)), UIColor(rgb: UInt32(bitPattern: innerColor)), UIColor(rgb: UInt32(bitPattern: patternColor)))
            } else if case let .pattern(_, file, _) = attribute {
                patternFile = file
            }
        }
        guard let colors else {
            self.coverHost.isHidden = true
            return
        }
        var files: [Int64: TelegramMediaFile] = [:]
        if let patternFile {
            files[patternFile.fileId.id] = patternFile
        }
        let _ = self.cover.update(
            transition: .immediate,
            component: AnyComponent(PeerInfoCoverComponent(
                context: context,
                subject: .custom(colors.0, colors.1, colors.2, patternFile?.fileId.id),
                files: files,
                isDark: false,
                avatarCenter: GiftStatsModelIconView.coverCenter,
                avatarScale: 1.0,
                defaultHeight: 300.0,
                gradientOnTop: true,
                avatarTransitionFraction: 0.0,
                patternTransitionFraction: 0.0
            )),
            environment: {},
            containerSize: CGSize(width: GiftStatsModelIconView.cardWidth, height: GiftStatsModelIconView.coverHeight)
        )
        if let view = self.cover.view, view.superview == nil {
            view.isUserInteractionEnabled = false
            self.coverHost.addSubview(view)
        }
        self.coverHost.isHidden = false
        self.setNeedsLayout()
    }

    private func update(context: AccountContext, file: TelegramMediaFile?) {
        guard let file else {
            self.fileId = nil
            self.disposable?.dispose()
            self.disposable = nil
            self.target.contents = nil
            return
        }
        guard self.fileId != file.fileId.id else {
            return
        }
        if self.fileId != nil {
            // Reused view: clear the previous model while the new one loads.
            self.target.contents = nil
        }
        self.fileId = file.fileId.id
        self.disposable?.dispose()
        let itemId = file.resource.id.stringRepresentation
        let size = CGSize(width: 96.0, height: 96.0)
        if !context.animationRenderer.loadFirstFrameSynchronously(target: self.target, cache: context.animationCache, itemId: itemId, size: size) {
            self.disposable = context.animationRenderer.loadFirstFrame(
                target: self.target,
                cache: context.animationCache,
                itemId: itemId,
                size: size,
                fetch: animationCacheFetchFile(
                    context: context,
                    userLocation: .other,
                    userContentType: .sticker,
                    resource: .media(media: .standalone(media: file), resource: file.resource),
                    type: AnimationCacheAnimationType(file: file),
                    keyframeOnly: false,
                    customColor: nil
                ),
                completion: { _, _ in }
            )
        }
    }
}
