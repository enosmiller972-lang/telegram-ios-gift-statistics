import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramCore
import TelegramPresentationData
import AccountContext
import AppBundle
import GiftStats
import GiftStatsScreen
import GiftAnimationComponent
import MultilineTextComponent
import ButtonComponent
import LottieComponent
import LottieSettings
import PeerTableCellComponent

/// Content of `GiftSaleMiniCardController`. The backdrop spans the whole card so there is no seam.
/// Labels take the width of the longest one and values are truncated, so long localizations stay inside.
final class GiftSaleMiniCardView: UIView {
    private static let headerHeight: CGFloat = 200.0
    private static let rowHeight: CGFloat = 44.0
    private static let inset: CGFloat = 16.0
    private static let buttonHeight: CGFloat = 52.0
    private static let closeSide: CGFloat = 44.0

    private let composition = ComponentView<Empty>()
    private let owner = ComponentView<Empty>()
    private let okButton = ComponentView<Empty>()
    private let moreIcon = ComponentView<Empty>()
    private let morePlay = ActionSlot<Void>()
    private let close: () -> Void
    private let more: (UIView) -> Void
    /// Card content at full size, clipped by the card; scaled about the model during the morph.
    let root = UIView()
    /// Fade in as the card grows and out first as it shrinks.
    private(set) var contentViews: [UIView] = []
    static let cornerRadius: CGFloat = 32.0
    /// Mirrors the model placement in `GiftCompositionComponent`.
    var modelCenter: CGPoint {
        return CGPoint(x: self.root.bounds.width / 2.0, y: 82.0)
    }
    static let modelSide: CGFloat = 136.0 * 0.9

    init(context: AccountContext, entry: GiftMiniCardEntry, width: CGFloat, close: @escaping () -> Void, more: @escaping (UIView) -> Void) {
        self.close = close
        self.more = more
        super.init(frame: .zero)
        let gift = entry.gift
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let strings = presentationData.strings
        let dateTimeFormat = presentationData.dateTimeFormat
        let palette = GiftTonalPalette.cached(gift: gift)
        let table = palette.table
        var outer = UIColor(white: 0.15, alpha: 1.0)
        var model: (String, StarGift.UniqueGift.Attribute.Rarity)?
        var symbol: (String, StarGift.UniqueGift.Attribute.Rarity)?
        var backdrop: (String, StarGift.UniqueGift.Attribute.Rarity)?
        for attribute in gift.attributes {
            switch attribute {
            case let .model(name, _, rarity, _):
                model = (name, rarity)
            case let .pattern(name, _, rarity):
                symbol = (name, rarity)
            case let .backdrop(name, _, _, outerColor, _, _, rarity):
                backdrop = (name, rarity)
                outer = UIColor(rgb: UInt32(bitPattern: outerColor))
            default:
                break
            }
        }

        func rarityText(_ rarity: StarGift.UniqueGift.Attribute.Rarity) -> String {
            switch rarity {
            case let .permille(value):
                return value == 0 ? "<0.1%" : formatPercentage(Float(value) * 0.1)
            case .epic:
                return strings.Gift_Attribute_Epic
            case .legendary:
                return strings.Gift_Attribute_Legendary
            case .rare:
                return strings.Gift_Attribute_Rare
            case .uncommon:
                return strings.Gift_Attribute_Uncommon
            }
        }
        enum Value {
            case text(String)
            case peer(EnginePeer)
        }
        var rows: [(label: String, value: Value, badge: String?)] = []
        if let owner = entry.owner {
            rows.append((strings.Gift_Unique_Owner, .peer(owner), nil))
        } else if let name = entry.ownerName {
            rows.append((strings.Gift_Unique_Owner, .text(name), nil))
        }
        if let model {
            rows.append((strings.Gift_Unique_Model, .text(model.0), rarityText(model.1)))
        }
        if let symbol {
            rows.append((strings.Gift_Unique_Symbol, .text(symbol.0), rarityText(symbol.1)))
        }
        if let backdrop {
            rows.append((strings.Gift_Unique_Backdrop, .text(backdrop.0), rarityText(backdrop.1)))
        }

        let side = GiftSaleMiniCardView.inset
        let contentWidth = width - side * 2.0
        let panelTop: CGFloat = GiftSaleMiniCardView.headerHeight + 44.0
        let panelHeight = CGFloat(rows.count) * GiftSaleMiniCardView.rowHeight
        let buttonY = panelTop + panelHeight + 16.0
        let height = buttonY + GiftSaleMiniCardView.buttonHeight + side
        self.bounds = CGRect(x: 0.0, y: 0.0, width: width, height: height)
        self.root.frame = self.bounds
        self.root.backgroundColor = outer
        self.addSubview(self.root)

        self.backgroundColor = outer
        self.layer.cornerRadius = GiftSaleMiniCardView.cornerRadius
        self.layer.cornerCurve = .continuous
        self.clipsToBounds = true

        let _ = self.composition.update(
            transition: .immediate,
            component: AnyComponent(GiftCompositionComponent(context: context, theme: presentationData.theme, subject: .unique(nil, gift), animationOffset: CGPoint(x: 0.0, y: -6.0), animationScale: 0.9, animateScaleOnTransition: false)),
            environment: {},
            containerSize: self.bounds.size
        )
        if let view = self.composition.view {
            view.frame = self.bounds
            self.root.addSubview(view)
        }

        let title = UILabel()
        title.textAlignment = .center
        title.lineBreakMode = .byTruncatingTail
        let titleText = NSMutableAttributedString(string: gift.title + " ", attributes: [.font: Font.bold(20.0), .foregroundColor: UIColor.white])
        titleText.append(NSAttributedString(string: "#" + presentationStringsFormattedNumber(gift.number, dateTimeFormat.groupingSeparator), attributes: [.font: Font.bold(20.0), .foregroundColor: UIColor(white: 1.0, alpha: 0.6)]))
        title.attributedText = titleText
        title.frame = CGRect(x: side + 28.0, y: 156.0, width: contentWidth - 56.0, height: 26.0)
        self.root.addSubview(title)

        let money = GiftStatsMoney(context: context)
        let price = NSMutableAttributedString()
        price.append(GiftStatsGram.attachment(fontSize: 15.0, color: .white))
        price.append(NSAttributedString(string: " " + money.gram(cents: entry.priceCents, dateTimeFormat: dateTimeFormat), attributes: [.font: Font.semibold(15.0), .foregroundColor: UIColor.white]))
        price.append(NSAttributedString(string: "  " + money.usd(cents: entry.priceCents, dateTimeFormat: dateTimeFormat), attributes: [.font: Font.regular(15.0), .foregroundColor: UIColor(white: 1.0, alpha: 0.6)]))
        let priceLabel = UILabel()
        priceLabel.attributedText = price
        priceLabel.lineBreakMode = .byTruncatingTail
        let priceTextSize = priceLabel.sizeThatFits(CGSize(width: contentWidth - 32.0, height: 30.0))
        let capsuleSize = CGSize(width: min(contentWidth, ceil(priceTextSize.width) + 28.0), height: 30.0)
        let capsule = GiftFlatTonalView()
        capsule.isUserInteractionEnabled = false
        capsule.frame = CGRect(x: floor((width - capsuleSize.width) / 2.0), y: 190.0, width: capsuleSize.width, height: capsuleSize.height)
        capsule.update(tile: GiftStatsTileStyle.surface(gift: gift), shape: .capsule)
        priceLabel.frame = CGRect(x: 14.0, y: floor((capsuleSize.height - ceil(priceTextSize.height)) / 2.0), width: capsuleSize.width - 28.0, height: ceil(priceTextSize.height))
        capsule.addSubview(priceLabel)
        capsule.isAccessibilityElement = true
        capsule.accessibilityLabel = entry.priceTitle + ", " + money.spokenGram(cents: entry.priceCents, dateTimeFormat: dateTimeFormat, strings: strings)
        self.root.addSubview(capsule)

        let labelFont = Font.regular(15.0)
        let valueFont = Font.regular(15.0)
        let labelWidth = min(contentWidth * 0.42, ceil(rows.map { ($0.label as NSString).size(withAttributes: [.font: labelFont]).width }.max() ?? 0.0))
        let panel = UIView(frame: CGRect(x: side, y: panelTop, width: contentWidth, height: panelHeight))
        panel.backgroundColor = table.panel
        panel.layer.cornerRadius = 20.0
        panel.layer.cornerCurve = .continuous
        self.root.addSubview(panel)
        let rowInset: CGFloat = 14.0
        for (i, row) in rows.enumerated() {
            let y = CGFloat(i) * GiftSaleMiniCardView.rowHeight
            let label = UILabel(frame: CGRect(x: rowInset, y: y, width: labelWidth, height: GiftSaleMiniCardView.rowHeight))
            label.font = labelFont
            label.textColor = table.label
            label.text = row.label
            label.lineBreakMode = .byTruncatingTail
            panel.addSubview(label)
            let valueX = rowInset + labelWidth + 14.0
            var valueRoom = contentWidth - valueX - rowInset
            var badgeView: UIView?
            if let badge = row.badge {
                let badgeLabel = UILabel()
                badgeLabel.font = Font.regular(12.0)
                badgeLabel.textColor = UIColor(white: 1.0, alpha: 0.85)
                badgeLabel.text = badge
                badgeLabel.textAlignment = .center
                let badgeWidth = ceil(badgeLabel.sizeThatFits(CGSize(width: 100.0, height: 20.0)).width) + 12.0
                badgeLabel.backgroundColor = UIColor(white: 1.0, alpha: 0.14)
                badgeLabel.layer.cornerRadius = 9.0
                badgeLabel.clipsToBounds = true
                badgeLabel.bounds = CGRect(x: 0.0, y: 0.0, width: badgeWidth, height: 18.0)
                badgeView = badgeLabel
                valueRoom -= badgeWidth + 6.0
            }
            var valueWidth: CGFloat = 0.0
            switch row.value {
            case let .text(text):
                let value = UILabel()
                value.font = valueFont
                value.textColor = .white
                value.text = text
                value.lineBreakMode = .byTruncatingTail
                valueWidth = min(max(20.0, valueRoom), ceil(value.sizeThatFits(CGSize(width: 400.0, height: 20.0)).width))
                value.frame = CGRect(x: valueX, y: y, width: valueWidth, height: GiftSaleMiniCardView.rowHeight)
                panel.addSubview(value)
            case let .peer(peer):
                let size = self.owner.update(
                    transition: .immediate,
                    component: AnyComponent(PeerTableCellComponent(context: context, theme: GiftViewFullBackdrop.theme, strings: strings, peer: peer)),
                    environment: {},
                    containerSize: CGSize(width: max(20.0, valueRoom), height: GiftSaleMiniCardView.rowHeight)
                )
                if let view = self.owner.view {
                    view.isUserInteractionEnabled = false
                    view.frame = CGRect(x: valueX, y: y + floor((GiftSaleMiniCardView.rowHeight - size.height) / 2.0), width: size.width, height: size.height)
                    panel.addSubview(view)
                }
                valueWidth = size.width
            }
            if let badgeView {
                badgeView.center = CGPoint(x: valueX + valueWidth + 6.0 + badgeView.bounds.width / 2.0, y: y + GiftSaleMiniCardView.rowHeight / 2.0)
                panel.addSubview(badgeView)
            }
            if i < rows.count - 1 {
                let line = UIView(frame: CGRect(x: rowInset, y: y + GiftSaleMiniCardView.rowHeight - UIScreenPixel, width: contentWidth - rowInset * 2.0, height: UIScreenPixel))
                line.backgroundColor = table.separator
                panel.addSubview(line)
            }
        }

        let buttonFrame = CGRect(x: side, y: buttonY, width: contentWidth, height: GiftSaleMiniCardView.buttonHeight)
        let surface = GiftFlatTonalView()
        surface.isUserInteractionEnabled = false
        surface.frame = buttonFrame
        surface.update(tile: GiftStatsTileStyle.surface(gift: gift), shape: .capsule)
        self.root.addSubview(surface)
        let _ = self.okButton.update(
            transition: .immediate,
            component: AnyComponent(ButtonComponent(
                background: ButtonComponent.Background(style: .glass, color: .clear, foreground: .white, pressedColor: UIColor(white: 1.0, alpha: 0.08)),
                content: AnyComponentWithIdentity(id: AnyHashable("ok"), component: AnyComponent(MultilineTextComponent(text: .plain(NSAttributedString(string: strings.Common_OK, font: Font.semibold(17.0), textColor: .white, paragraphAlignment: .center))))),
                isEnabled: true,
                displaysProgress: false,
                action: { [weak self] in
                    self?.close()
                }
            )),
            environment: {},
            containerSize: buttonFrame.size
        )
        var okView: UIView = surface
        if let view = self.okButton.view {
            view.frame = buttonFrame
            self.root.addSubview(view)
            okView = view
        }

        let cornerTile = GiftStatsTileStyle.surface(gift: gift, outerShare: GiftViewFullBackdropComponent.cornerOuterShare(width: width))
        let cornerSide = GiftSaleMiniCardView.closeSide
        let cross = GiftFlatTonalView()
        cross.frame = CGRect(x: 14.0, y: 14.0, width: cornerSide, height: cornerSide)
        cross.update(tile: cornerTile, shape: .capsule)
        cross.label = strings.Common_Close
        cross.action = { [weak self] in
            self?.close()
        }
        let crossIcon = UIImageView(image: generateTintedImage(image: UIImage(bundleImageName: "Navigation/Close"), color: .white))
        crossIcon.contentMode = .center
        crossIcon.frame = cross.bounds
        crossIcon.isUserInteractionEnabled = false
        cross.addSubview(crossIcon)
        self.root.addSubview(cross)

        let moreButton = GiftFlatTonalView()
        moreButton.frame = CGRect(x: width - 14.0 - cornerSide, y: 14.0, width: cornerSide, height: cornerSide)
        moreButton.update(tile: cornerTile, shape: .capsule)
        moreButton.label = strings.Common_More
        let moreIconSize = self.moreIcon.update(
            transition: .immediate,
            component: AnyComponent(LottieComponent(content: LottieComponent.AppBundleContent(name: "anim_morewide"), color: .white, size: CGSize(width: 32.0, height: 32.0), playOnce: self.morePlay, lottieSettings: .noAccountFallback)),
            environment: {},
            containerSize: moreButton.bounds.size
        )
        if let iconView = self.moreIcon.view {
            iconView.isUserInteractionEnabled = false
            iconView.frame = CGRect(x: floor((cornerSide - moreIconSize.width) / 2.0), y: floor((cornerSide - moreIconSize.height) / 2.0), width: moreIconSize.width, height: moreIconSize.height)
            moreButton.addSubview(iconView)
        }
        moreButton.action = { [weak self, weak moreButton] in
            guard let self, let moreButton else {
                return
            }
            self.morePlay.invoke(Void())
            self.more(moreButton)
        }
        self.root.addSubview(moreButton)
        self.contentViews = [title, capsule, panel, surface, okView, cross, moreButton]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `p` goes from 0 (`source`, the row thumbnail in superview coordinates) to 1 (`target`). Content is scaled about the model;
    /// texts and the panel fade in over the second half.
    func applyMorph(p: CGFloat, source: CGRect, target: CGRect, sourceRadius: CGFloat) {
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
            return a + (b - a) * p
        }
        let frame = CGRect(x: lerp(source.minX, target.minX), y: lerp(source.minY, target.minY), width: max(1.0, lerp(source.width, target.width)), height: max(1.0, lerp(source.height, target.height)))
        self.transform = .identity
        self.bounds = CGRect(origin: .zero, size: frame.size)
        self.center = CGPoint(x: frame.midX, y: frame.midY)
        self.layer.cornerRadius = max(0.0, lerp(sourceRadius, GiftSaleMiniCardView.cornerRadius))
        // The row model fills 80% of its thumbnail.
        let startScale = source.width * 0.8 / GiftSaleMiniCardView.modelSide
        let scale = lerp(startScale, 1.0)
        let model = CGPoint(x: lerp(source.midX, target.minX + self.modelCenter.x), y: lerp(source.midY, target.minY + self.modelCenter.y))
        let local = CGPoint(x: model.x - frame.minX, y: model.y - frame.minY)
        let rootSize = self.root.bounds.size
        self.root.transform = CGAffineTransform(scaleX: scale, y: scale)
        self.root.center = CGPoint(x: local.x + (rootSize.width / 2.0 - self.modelCenter.x) * scale, y: local.y + (rootSize.height / 2.0 - self.modelCenter.y) * scale)
        let t = min(1.0, max(0.0, (p - 0.45) / 0.4))
        let shown = t * t * (3.0 - 2.0 * t)
        for view in self.contentViews {
            view.alpha = shown
        }
    }

    func finishAnimation(maximumDuration: Double, completion: @escaping () -> Void) {
        guard let view = self.composition.view as? GiftCompositionComponent.View else {
            completion()
            return
        }
        view.finishAnimation(maximumDuration: maximumDuration, completion: completion)
    }

    func settle() {
        self.root.transform = .identity
        self.root.frame = CGRect(origin: .zero, size: self.root.bounds.size)
        self.bounds = CGRect(origin: .zero, size: self.root.bounds.size)
        self.layer.cornerRadius = GiftSaleMiniCardView.cornerRadius
        for view in self.contentViews {
            view.alpha = 1.0
        }
    }
}
