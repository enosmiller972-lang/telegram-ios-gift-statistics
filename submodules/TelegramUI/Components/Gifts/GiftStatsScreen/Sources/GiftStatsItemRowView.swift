import Foundation
import UIKit
import Display
import TelegramCore
import TelegramPresentationData
import AccountContext
import GiftStats

/// The user's own gift laid out like a sales log row (`GiftStatsSalesRowView`), with a sell/unlist button on the trailing side.
final class GiftStatsItemRowView: UIView, UIGestureRecognizerDelegate {
    private static let iconSize: CGFloat = GiftStatsSalesRowView.iconSize
    private static let minimumTextWidth: CGFloat = 64.0
    private static let textGap: CGFloat = 8.0
    private static let numberFont = Font.semibold(15.0)
    private static let priceFont = Font.semibold(15.0)
    private static let smallFont = Font.regular(13.0)
    private static let minimumPriceFontSize: CGFloat = 11.0
    private static let buttonFont = Font.semibold(15.0)
    private static let buttonHeight: CGFloat = 30.0
    private static let buttonPadding: CGFloat = 14.0

    /// Everything except the price.
    let details = UIView()
    private let icon = GiftStatsModelIconView()
    private let number = GiftStatsNumericTextView()
    private let modelLabel = UILabel()
    private let estimateLabel = UILabel()
    private let button = GiftStatsItemButton()
    private let glyph = GiftStatsGram.make()
    private let price = GiftStatsNumericTextView()
    private var action: (() -> Void)?
    private var open: ((UIView) -> Void)?
    private let highlight = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.details.isUserInteractionEnabled = true
        self.highlight.isUserInteractionEnabled = false
        self.highlight.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
        self.highlight.alpha = 0.0
        self.addSubview(self.highlight)
        self.addSubview(self.details)
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.rowTapped))
        tap.delegate = self
        self.addGestureRecognizer(tap)
        self.details.addSubview(self.icon)
        self.details.addSubview(self.number)
        for label in [self.modelLabel, self.estimateLabel] {
            label.font = GiftStatsItemRowView.smallFont
            label.lineBreakMode = .byTruncatingTail
            label.isAccessibilityElement = false
            self.details.addSubview(label)
        }
        self.details.addSubview(self.button)
        self.button.addTarget(self, action: #selector(self.buttonPressed), for: .touchUpInside)
        self.glyph.color = GiftStatsLook.textColor
        self.addSubview(self.glyph)
        self.addSubview(self.price)
        // VoiceOver reads the row summary on the number.
        self.price.isAccessibilityElement = false
        self.price.accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return !(touch.view?.isDescendant(of: self.button) ?? false)
    }

    @objc private func rowTapped() {
        guard let open = self.open else {
            return
        }
        self.highlight.alpha = 1.0
        UIView.animate(withDuration: 0.3, delay: 0.05, options: [.curveEaseOut], animations: {
            self.highlight.alpha = 0.0
        })
        open(self.icon)
    }

    @objc private func buttonPressed() {
        self.action?()
    }

    func update(gift: StarGift.UniqueGift, item: GiftStatsYourItem, context: AccountContext, money: GiftStatsMoney, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat, palette: GiftTonalPalette, buttonFill: UIColor, buttonForeground: UIColor, width: CGFloat, isRTL: Bool, action: @escaping () -> Void, open: ((UIView) -> Void)? = nil) -> CGSize {
        self.action = action
        self.open = open
        self.highlight.frame = CGRect(x: 0.0, y: 0.0, width: width, height: GiftStatsSalesRowView.height)
        self.highlight.layer.cornerRadius = GiftTonalPalette.cornerRadius
        self.highlight.layer.cornerCurve = .continuous
        let inset = GiftTonalPalette.inset
        let height = GiftStatsSalesRowView.height
        self.details.frame = CGRect(x: 0.0, y: 0.0, width: width, height: height)
        self.modelLabel.textColor = palette.label
        self.estimateLabel.textColor = palette.dim
        func placed(_ frame: CGRect) -> CGRect {
            return isRTL ? CGRect(x: width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height) : frame
        }
        let leadingAlignment: NSTextAlignment = isRTL ? .right : .left
        self.modelLabel.textAlignment = leadingAlignment
        self.estimateLabel.textAlignment = leadingAlignment

        var modelName = ""
        var modelFile: TelegramMediaFile?
        var backdrop: GiftSaleBackdrop?
        for attribute in gift.attributes {
            if case let .model(name, file, _, _) = attribute {
                modelName = name
                modelFile = file
            } else if case let .backdrop(_, _, innerColor, outerColor, _, _, _) = attribute {
                backdrop = GiftSaleBackdrop(innerColor: innerColor, outerColor: outerColor)
            }
        }
        self.icon.frame = placed(CGRect(x: inset, y: floor((height - GiftStatsItemRowView.iconSize) / 2.0), width: GiftStatsItemRowView.iconSize, height: GiftStatsItemRowView.iconSize))
        self.icon.update(context: context, file: modelFile, backdrop: backdrop, gift: gift)

        let firstHeight = ceil(GiftStatsItemRowView.priceFont.lineHeight)
        let secondHeight = ceil(GiftStatsItemRowView.smallFont.lineHeight)
        let top = floor((height - firstHeight - 2.0 - secondHeight) / 2.0)
        let secondY = top + firstHeight + 2.0

        let buttonTitle = item.isListed ? strings.Gift_Stats_Unlist : strings.Gift_Stats_Sell
        // Fits its title, up to a third of the row.
        let titleWidth = ceil((buttonTitle as NSString).size(withAttributes: [.font: GiftStatsItemRowView.buttonFont]).width)
        let buttonSize = CGSize(width: min(floor((width - inset * 2.0) / 3.0), titleWidth + GiftStatsItemRowView.buttonPadding * 2.0), height: GiftStatsItemRowView.buttonHeight)
        let buttonX = width - inset - buttonSize.width
        self.button.frame = placed(CGRect(origin: CGPoint(x: buttonX, y: floor((height - buttonSize.height) / 2.0)), size: buttonSize))
        self.button.update(title: buttonTitle, font: GiftStatsItemRowView.buttonFont, fill: buttonFill, foreground: buttonForeground)

        // Aligned with the log's price column; shifts left for a wide button, then shrinks its font.
        let priceText = money.gram(cents: item.usdCents, dateTimeFormat: dateTimeFormat)
        let estimateText = strings.Gift_Stats_AveragePrice
        let wanted = max(
            GiftStatsGram.side(fontSize: 15.0) + GiftStatsGram.gap(fontSize: 15.0) + GiftStatsNumericTextView.width(of: priceText, font: GiftStatsItemRowView.priceFont),
            ceil((estimateText as NSString).size(withAttributes: [.font: GiftStatsItemRowView.smallFont]).width)
        )
        let textX = inset + GiftStatsItemRowView.iconSize + 10.0
        let leftmost = textX + GiftStatsItemRowView.minimumTextWidth + GiftStatsItemRowView.textGap
        let priceX = max(leftmost, min(GiftStatsSalesRowView.priceColumn(width: width), buttonX - GiftStatsItemRowView.textGap - wanted))
        let priceRoom = max(20.0, buttonX - GiftStatsItemRowView.textGap - priceX)
        var fontSize: CGFloat = 15.0
        var priceFont = GiftStatsItemRowView.priceFont
        while fontSize > GiftStatsItemRowView.minimumPriceFontSize, GiftStatsGram.side(fontSize: fontSize) + GiftStatsGram.gap(fontSize: fontSize) + GiftStatsNumericTextView.width(of: priceText, font: priceFont) > priceRoom {
            fontSize -= 1.0
            priceFont = Font.semibold(fontSize)
        }
        let glyphSide = GiftStatsGram.side(fontSize: fontSize)
        let priceSize = self.price.update(text: priceText, font: priceFont, color: GiftStatsLook.textColor, animated: false)
        let glyphFrame = CGRect(x: priceX, y: floor(top + firstHeight / 2.0 - glyphSide / 2.0), width: glyphSide, height: glyphSide)
        let priceFrame = CGRect(x: priceX + glyphSide + GiftStatsGram.gap(fontSize: fontSize), y: top + floor((firstHeight - priceSize.height) / 2.0), width: priceSize.width, height: priceSize.height)
        self.glyph.frame = placed(glyphFrame)
        self.price.frame = placed(priceFrame)
        self.estimateLabel.text = estimateText
        self.estimateLabel.frame = placed(CGRect(x: priceX, y: secondY, width: priceRoom, height: secondHeight))

        let textWidth = max(20.0, priceX - GiftStatsItemRowView.textGap - textX)
        let numberText = "#" + presentationStringsFormattedNumber(gift.number, dateTimeFormat.groupingSeparator)
        var numberFont = GiftStatsItemRowView.numberFont
        while numberFont.pointSize > GiftStatsItemRowView.minimumPriceFontSize, GiftStatsNumericTextView.width(of: numberText, font: numberFont) > textWidth {
            numberFont = Font.semibold(numberFont.pointSize - 1.0)
        }
        let numberSize = self.number.update(text: numberText, font: numberFont, color: GiftStatsLook.textColor, animated: false)
        self.number.frame = placed(CGRect(x: textX, y: top + floor((firstHeight - numberSize.height) / 2.0), width: numberSize.width, height: numberSize.height))
        self.modelLabel.text = modelName
        self.modelLabel.frame = placed(CGRect(x: textX, y: secondY, width: textWidth, height: secondHeight))

        let spokenPrice = money.spokenGram(cents: item.usdCents, dateTimeFormat: dateTimeFormat, strings: strings)
        self.number.spoken = GiftStatsFormat.join([numberText, modelName, spokenPrice, estimateText], strings: strings)
        self.button.accessibilityLabel = buttonTitle
        return CGSize(width: width, height: height)
    }
}

private final class GiftStatsItemButton: UIControl {
    private let label = UILabel()
    private static let padding: CGFloat = 10.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.label.adjustsFontSizeToFitWidth = true
        self.label.minimumScaleFactor = 0.7
        self.label.textAlignment = .center
        self.label.isUserInteractionEnabled = false
        self.addSubview(self.label)
        self.isAccessibilityElement = true
        self.accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            self.alpha = self.isHighlighted ? 0.65 : 1.0
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.label.frame = self.bounds.insetBy(dx: GiftStatsItemButton.padding, dy: 0.0)
    }

    func update(title: String, font: UIFont, fill: UIColor, foreground: UIColor) {
        self.backgroundColor = fill
        self.layer.cornerRadius = self.bounds.height / 2.0
        self.layer.cornerCurve = .continuous
        self.label.font = font
        self.label.textColor = foreground
        self.label.text = title
        self.setNeedsLayout()
    }
}
