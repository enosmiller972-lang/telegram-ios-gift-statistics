import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramCore
import TelegramPresentationData
import AccountContext
import GiftStats

/// A sales log row: model and number, price in Gram over USD, market over time ago. Columns align across rows.
final class GiftStatsSalesRowView: UIView {
    static let height: CGFloat = 60.0
    static let iconSize: CGFloat = 40.0
    /// Left of centre, leaving room for long trailing texts (market names, localized sell button).
    static func priceColumn(width: CGFloat) -> CGFloat {
        return floor(width * 0.46)
    }
    private static let textGap: CGFloat = 8.0
    private static let numberFont = Font.semibold(15.0)
    private static let priceFont = Font.semibold(15.0)
    private static let marketFont = Font.regular(15.0)
    private static let smallFont = Font.regular(13.0)
    private static let minimumRightWidth: CGFloat = 40.0
    private static let minimumPriceFontSize: CGFloat = 11.0

    private let icon = GiftStatsModelIconView()
    /// The card opened from the row grows out of this view.
    var iconView: UIView {
        return self.icon
    }
    private let number = GiftStatsNumericTextView()
    private let modelLabel = UILabel()
    let price = GiftStatsNumericTextView()
    let glyph = GiftStatsGram.make()
    private let usdLabel = UILabel()
    private let marketLabel = UILabel()
    private let timeLabel = UILabel()
    private let separator = UIView()
    private var sale: GiftSale?
    /// Called when the model image arrives after `update`.
    var contentChanged: (() -> Void)?
    /// nil when the sold gift is unknown.
    var tapped: (() -> Void)? {
        didSet {
            self.tapRecognizer.isEnabled = self.tapped != nil
            self.accessibilityTraits = self.tapped != nil ? [.button] : [.staticText]
        }
    }
    private lazy var tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.handleTap))
    private let highlight = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.icon.contentUpdated = { [weak self] in
            self?.contentChanged?()
        }
        self.isAccessibilityElement = true
        self.accessibilityTraits = .staticText
        self.addSubview(self.icon)
        self.addSubview(self.number)
        self.modelLabel.font = GiftStatsSalesRowView.smallFont
        self.modelLabel.lineBreakMode = .byTruncatingTail
        self.addSubview(self.modelLabel)
        self.usdLabel.font = GiftStatsSalesRowView.smallFont
        self.usdLabel.lineBreakMode = .byTruncatingTail
        self.addSubview(self.usdLabel)
        self.marketLabel.font = GiftStatsSalesRowView.marketFont
        self.marketLabel.lineBreakMode = .byTruncatingTail
        self.addSubview(self.marketLabel)
        self.timeLabel.font = GiftStatsSalesRowView.smallFont
        self.timeLabel.lineBreakMode = .byTruncatingTail
        self.addSubview(self.timeLabel)
        self.glyph.color = GiftStatsLook.textColor
        self.addSubview(self.glyph)
        self.addSubview(self.price)
        self.addSubview(self.separator)
        self.highlight.isUserInteractionEnabled = false
        self.highlight.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
        self.highlight.alpha = 0.0
        self.insertSubview(self.highlight, at: 0)
        self.tapRecognizer.isEnabled = false
        self.addGestureRecognizer(self.tapRecognizer)
    }

    @objc private func handleTap() {
        guard let tapped = self.tapped else {
            return
        }
        self.highlight.alpha = 1.0
        UIView.animate(withDuration: 0.3, delay: 0.05, options: [.curveEaseOut], animations: {
            self.highlight.alpha = 0.0
        })
        tapped()
    }

    override func accessibilityActivate() -> Bool {
        guard let tapped = self.tapped else {
            return false
        }
        tapped()
        return true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForReuse() {
        self.layer.removeAllAnimations()
        self.alpha = 1.0
        self.transform = .identity
    }

    /// `animated` applies only when the row switches to a different sale.
    func update(sale: GiftSale, context: AccountContext, money: GiftStatsMoney, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat, palette: GiftTonalPalette, now: Int32, width: CGFloat, isLast: Bool, isRTL: Bool, animated: Bool) {
        let inset = GiftTonalPalette.inset
        let height = GiftStatsSalesRowView.height
        let isChanged = self.sale != nil && self.sale != sale
        self.sale = sale
        let isAnimated = animated && isChanged
        self.modelLabel.textColor = palette.label
        self.marketLabel.textColor = palette.label
        self.usdLabel.textColor = palette.dim
        self.timeLabel.textColor = palette.dim
        self.separator.backgroundColor = palette.separator
        // Laid out left to right, then mirrored for RTL.
        func placed(_ frame: CGRect) -> CGRect {
            return isRTL ? CGRect(x: width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height) : frame
        }
        let leadingAlignment: NSTextAlignment = isRTL ? .right : .left
        let trailingAlignment: NSTextAlignment = isRTL ? .left : .right
        self.modelLabel.textAlignment = leadingAlignment
        self.usdLabel.textAlignment = leadingAlignment
        self.marketLabel.textAlignment = trailingAlignment
        self.timeLabel.textAlignment = trailingAlignment
        let iconFrame = CGRect(x: inset, y: floor((height - GiftStatsSalesRowView.iconSize) / 2.0), width: GiftStatsSalesRowView.iconSize, height: GiftStatsSalesRowView.iconSize)
        self.icon.frame = placed(iconFrame)
        self.icon.update(context: context, file: sale.modelFile, backdrop: sale.backdrop, gift: sale.gift)

        let firstHeight = ceil(GiftStatsSalesRowView.priceFont.lineHeight)
        let secondHeight = ceil(GiftStatsSalesRowView.smallFont.lineHeight)
        let top = floor((height - firstHeight - 2.0 - secondHeight) / 2.0)
        let secondY = top + firstHeight + 2.0

        // The price is never truncated; its font shrinks instead.
        let priceX = GiftStatsSalesRowView.priceColumn(width: width)
        let priceText = money.gram(cents: sale.priceUsd, dateTimeFormat: dateTimeFormat)
        var priceFont = GiftStatsSalesRowView.priceFont
        let wantedWidth = GiftStatsGram.side(fontSize: 15.0) + GiftStatsGram.gap(fontSize: 15.0) + GiftStatsNumericTextView.width(of: priceText, font: priceFont)

        // At most 40% of the row and whatever the price leaves; truncated.
        self.marketLabel.text = sale.market.title
        self.timeLabel.text = GiftStatsFormat.ago(date: sale.date, now: now, strings: strings)
        let timeWidth = ceil(self.timeLabel.sizeThatFits(CGSize(width: 400.0, height: secondHeight)).width)
        let marketWidth = ceil(self.marketLabel.sizeThatFits(CGSize(width: 400.0, height: firstHeight)).width)
        let rightMaximum = max(GiftStatsSalesRowView.minimumRightWidth, min(floor((width - inset * 2.0) * 0.4), width - inset - priceX - GiftStatsSalesRowView.textGap - wantedWidth))
        let rightWidth = min(max(marketWidth, timeWidth), rightMaximum)
        let rightX = width - inset - rightWidth
        self.marketLabel.frame = placed(CGRect(x: rightX, y: top, width: rightWidth, height: firstHeight))
        self.timeLabel.frame = placed(CGRect(x: rightX, y: secondY, width: rightWidth, height: secondHeight))

        let priceRoom = max(20.0, rightX - GiftStatsSalesRowView.textGap - priceX)
        var fontSize: CGFloat = 15.0
        func roomForPrice(_ fontSize: CGFloat, _ font: UIFont) -> CGFloat {
            return GiftStatsGram.side(fontSize: fontSize) + GiftStatsGram.gap(fontSize: fontSize) + GiftStatsNumericTextView.width(of: priceText, font: font)
        }
        while fontSize > GiftStatsSalesRowView.minimumPriceFontSize, roomForPrice(fontSize, priceFont) > priceRoom {
            fontSize -= 1.0
            priceFont = Font.semibold(fontSize)
        }
        let glyphSide = GiftStatsGram.side(fontSize: fontSize)
        let glyphGap = GiftStatsGram.gap(fontSize: fontSize)
        let priceSize = self.price.update(text: priceText, font: priceFont, color: GiftStatsLook.textColor, animated: isAnimated)
        let spokenPrice = money.spokenGram(cents: sale.priceUsd, dateTimeFormat: dateTimeFormat, strings: strings)
        self.price.spoken = spokenPrice
        let priceFrame = placed(CGRect(x: priceX + glyphSide + glyphGap, y: top + floor((firstHeight - priceSize.height) / 2.0), width: priceSize.width, height: priceSize.height))
        let glyphFrame = placed(CGRect(x: priceX, y: floor(top + firstHeight / 2.0 - glyphSide / 2.0), width: glyphSide, height: glyphSide))
        let usdText = money.usd(cents: sale.priceUsd, dateTimeFormat: dateTimeFormat)
        self.usdLabel.text = usdText
        self.usdLabel.frame = placed(CGRect(x: priceX, y: secondY, width: priceRoom, height: secondHeight))

        let textX = inset + GiftStatsSalesRowView.iconSize + 10.0
        let textWidth = max(20.0, priceX - GiftStatsSalesRowView.textGap - textX)
        let numberText = "#" + presentationStringsFormattedNumber(sale.number, dateTimeFormat.groupingSeparator)
        var numberFont = GiftStatsSalesRowView.numberFont
        while numberFont.pointSize > GiftStatsSalesRowView.minimumPriceFontSize, GiftStatsNumericTextView.width(of: numberText, font: numberFont) > textWidth {
            numberFont = Font.semibold(numberFont.pointSize - 1.0)
        }
        let numberSize = self.number.update(text: numberText, font: numberFont, color: GiftStatsLook.textColor, animated: isAnimated)
        let numberFrame = placed(CGRect(x: textX, y: top + floor((firstHeight - numberSize.height) / 2.0), width: numberSize.width, height: numberSize.height))
        self.number.bounds = CGRect(origin: .zero, size: numberSize)
        self.number.center = CGPoint(x: numberFrame.midX, y: numberFrame.midY)
        self.modelLabel.text = sale.modelName
        self.modelLabel.frame = placed(CGRect(x: textX, y: secondY, width: textWidth, height: secondHeight))

        GiftStatsNumericTextView.move(animated: isAnimated) {
            self.price.bounds = CGRect(origin: .zero, size: priceFrame.size)
            self.price.center = CGPoint(x: priceFrame.midX, y: priceFrame.midY)
            self.glyph.frame = glyphFrame
        }

        self.accessibilityLabel = GiftStatsFormat.join([numberText, sale.modelName, spokenPrice, sale.market.title, GiftStatsFormat.spokenAgo(date: sale.date, now: now, strings: strings)], strings: strings)
        self.highlight.frame = CGRect(x: 0.0, y: 0.0, width: width, height: height)
        self.separator.isHidden = isLast
        self.separator.frame = CGRect(x: inset, y: height - UIScreenPixel, width: width - inset * 2.0, height: UIScreenPixel)
    }
}
