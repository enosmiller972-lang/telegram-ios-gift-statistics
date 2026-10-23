import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramCore
import AccountContext
import AppBundle
import LocalMediaResources
import PeerInfoCoverComponent

// Shared by the Craft Gift screen and the gift stats screen.
public final class GiftCraftBackdropView: UIView {
    public static let focusY: CGFloat = 169.0
    public static let topCornerRadius: CGFloat = 40.0
    private static let patternReach: CGFloat = 169.0
    private static let anvilId: Int64 = -123456789

    private let base = SimpleGradientLayer()
    private let glow = SimpleGradientLayer()
    private let pattern = ComponentView<Empty>()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.base.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        self.base.type = .axial
        self.base.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.base.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.layer.addSublayer(self.base)
        self.glow.type = .radial
        self.glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.glow.endPoint = CGPoint(x: 0.0, y: 1.0)
        self.layer.addSublayer(self.glow)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func anvilFile() -> TelegramMediaFile {
        let path = getAppBundle().url(forResource: "Anvil", withExtension: "tgs")?.path ?? ""
        return TelegramMediaFile(
            fileId: EngineMedia.Id(namespace: Namespaces.Media.CloudFile, id: GiftCraftBackdropView.anvilId),
            partialReference: nil,
            resource: BundleResource(name: "Anvil", path: path),
            previewRepresentations: [],
            videoThumbnails: [],
            immediateThumbnailData: nil,
            mimeType: "application/x-tgsticker",
            size: nil,
            attributes: [
                .FileName(fileName: "sticker.tgs"),
                .CustomEmoji(isPremium: false, isSingleColor: true, alt: "", packReference: .animatedEmojiAnimations)
            ],
            alternativeRepresentations: []
        )
    }

    // topExtension also fills that many points above the view's top edge (for overscroll).
    public func update(context: AccountContext, colors: GiftCraftBackdropColors, size: CGSize, focusY: CGFloat = GiftCraftBackdropView.focusY, topCornerRadius: CGFloat = GiftCraftBackdropView.topCornerRadius, showsPattern: Bool = true, topExtension: CGFloat = 0.0, transition: ComponentTransition) {
        self.base.cornerRadius = topCornerRadius
        if topExtension > 0.0 {
            // Flat top colour over the extension; the gradient starts at the view's top edge.
            let total = size.height + topExtension
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.base.locations = [0.0, NSNumber(value: Double(topExtension / total)), 1.0]
            CATransaction.commit()
            transition.setGradientColors(layer: self.base, colors: [colors.top, colors.top, colors.bottom])
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.base.locations = nil
            CATransaction.commit()
            transition.setGradientColors(layer: self.base, colors: [colors.top, colors.bottom])
        }
        transition.setGradientColors(layer: self.glow, colors: [colors.glow, colors.glow.withAlphaComponent(0.0)])
        transition.setFrame(layer: self.base, frame: CGRect(x: 0.0, y: -topExtension, width: size.width, height: size.height + topExtension))
        transition.setFrame(layer: self.glow, frame: CGRect(origin: CGPoint(x: 0.0, y: focusY - size.width * 0.5), size: CGSize(width: size.width, height: size.width)))

        guard showsPattern else {
            self.pattern.view?.removeFromSuperview()
            return
        }
        let anvil = GiftCraftBackdropView.anvilFile()
        var patternTransition = transition
        let patternSize = self.pattern.update(
            transition: patternTransition,
            component: AnyComponent(PeerInfoCoverComponent(
                context: context,
                subject: .custom(.clear, .clear, UIColor(rgb: 0x000000), anvil.fileId.id),
                files: [anvil.fileId.id: anvil],
                isDark: false,
                avatarCenter: CGPoint(x: size.width / 2.0, y: focusY),
                avatarSize: CGSize(width: 130.0, height: 130.0),
                avatarScale: 1.0,
                defaultHeight: 300.0,
                gradientOnTop: true,
                avatarTransitionFraction: 0.0,
                patternTransitionFraction: 0.0,
                patternIconScale: 1.5
            )),
            environment: {},
            containerSize: CGSize(width: size.width, height: focusY + GiftCraftBackdropView.patternReach)
        )
        if let patternView = self.pattern.view {
            if patternView.superview == nil {
                patternTransition = .immediate
                patternView.clipsToBounds = true
                patternView.isUserInteractionEnabled = false
                self.addSubview(patternView)
            }
            patternTransition.setFrame(view: patternView, frame: CGRect(origin: .zero, size: patternSize))
        }
    }
}
