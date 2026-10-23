import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramPresentationData

/// Key statistics number tile with animated counter and title.
final class GiftStatsValueTileView: UIView {
    static let height: CGFloat = GiftStatsTileStyle.height
    static let spacing: CGFloat = GiftStatsTileStyle.spacing
    private static let labelFont = GiftStatsTileStyle.labelFont
    private static let sideMargin: CGFloat = 6.0
    private static let minimumFontSize: CGFloat = 12.0

    static func numberFont(size: CGFloat) -> UIFont {
        return Font.with(size: size, design: .round, weight: .bold)
    }

    private let flat = GiftFlatTonalView()
    private let value = GiftStatsNumericTextView()
    private let label = UILabel()
    private let dim = GiftStatsNumericTextView()
    private let glyph = GiftStatsGram.make()

    override init(frame: CGRect) {
        super.init(frame: frame)
        // The tile is one element for a screen reader: "Floor, 4.4 Grams, ~$5.85".
        self.isAccessibilityElement = true
        self.accessibilityTraits = .staticText
        self.label.font = GiftStatsValueTileView.labelFont
        self.label.textColor = GiftStatsTileStyle.labelColor
        self.label.textAlignment = .center
        self.label.isUserInteractionEnabled = false
        self.addSubview(self.flat)
        self.flat.addSubview(self.label)
        self.flat.addSubview(self.dim)
        self.flat.addSubview(self.value)
        self.flat.addSubview(self.glyph)
        self.glyph.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(text: String, spoken: String? = nil, title: String, isGram: Bool = false, dim: String? = nil, tile: GiftStatsTileSurface, size: CGSize, strings: PresentationStrings, transition: ComponentTransition) {
        transition.setFrame(view: self.flat, frame: CGRect(origin: .zero, size: size))
        self.flat.update(tile: tile, transition: transition)
        let secondary = GiftStatsContrast.legible(GiftStatsLook.secondaryTextColor, over: [tile.flat.fill])
        self.label.textColor = GiftStatsContrast.legible(GiftStatsTileStyle.labelColor, over: [tile.flat.fill])

        var isAnimated = true
        if case .none = transition.animation {
            isAnimated = false
        }
        let room = size.width - GiftStatsValueTileView.sideMargin * 2.0
        var fontSize: CGFloat = 18.0
        var font = GiftStatsValueTileView.numberFont(size: fontSize)
        func roomForGlyph(_ fontSize: CGFloat) -> CGFloat {
            return isGram ? GiftStatsGram.side(fontSize: fontSize) + GiftStatsGram.gap(fontSize: fontSize) : 0.0
        }
        while fontSize > GiftStatsValueTileView.minimumFontSize, GiftStatsNumericTextView.width(of: text, font: font) + roomForGlyph(fontSize) > room {
            fontSize -= 1.0
            font = GiftStatsValueTileView.numberFont(size: fontSize)
        }
        let glyphSide = GiftStatsGram.side(fontSize: fontSize)
        let glyphRoom = roomForGlyph(fontSize)
        let numberSize = self.value.update(text: text, font: font, color: .white, animated: isAnimated)
        self.value.spoken = spoken
        let groupX = floor((size.width - glyphRoom - numberSize.width) / 2.0)
        let valueFrame = CGRect(origin: CGPoint(x: groupX + glyphRoom, y: floorToScreenPixels(GiftStatsTileStyle.iconCenterY - numberSize.height * 0.5)), size: numberSize)
        let glyphFrame = CGRect(x: groupX, y: floorToScreenPixels(GiftStatsTileStyle.iconCenterY - glyphSide / 2.0), width: glyphSide, height: glyphSide)
        let wasGlyphHidden = self.glyph.isHidden
        self.glyph.color = .white
        self.glyph.isHidden = !isGram
        if wasGlyphHidden {
            self.glyph.frame = glyphFrame
        }

        self.label.text = title
        let labelWidth = min(ceil(self.label.sizeThatFits(CGSize(width: room, height: 16.0)).width), room)
        let labelHeight = GiftStatsNumericTextView.lineHeight(of: GiftStatsValueTileView.labelFont)
        let dimFont = GiftStatsValueTileView.labelFont
        let spaceWidth = GiftStatsNumericTextView.width(of: " ", font: dimFont)
        var dimText = dim ?? ""
        if !dimText.isEmpty, labelWidth + spaceWidth + GiftStatsNumericTextView.width(of: dimText, font: dimFont) > room {
            dimText = ""
        }
        let dimSize = self.dim.update(text: dimText, font: dimFont, color: secondary, animated: isAnimated)
        let lineGap = dimText.isEmpty ? 0.0 : spaceWidth
        let lineX = floor((size.width - labelWidth - lineGap - dimSize.width) / 2.0)
        let labelFrame = CGRect(x: lineX, y: floorToScreenPixels(GiftStatsTileStyle.labelCenterY - labelHeight * 0.5), width: labelWidth, height: labelHeight)
        let dimFrame = CGRect(x: lineX + labelWidth + lineGap, y: labelFrame.minY, width: dimSize.width, height: labelHeight)
        self.accessibilityLabel = GiftStatsFormat.join([title, spoken ?? text, dim ?? ""], strings: strings)
        GiftStatsNumericTextView.move(animated: isAnimated) {
            self.value.bounds = CGRect(origin: .zero, size: valueFrame.size)
            self.value.center = CGPoint(x: valueFrame.midX, y: valueFrame.midY)
            self.glyph.frame = glyphFrame
            self.label.frame = labelFrame
            self.dim.bounds = CGRect(origin: .zero, size: dimFrame.size)
            self.dim.center = CGPoint(x: dimFrame.midX, y: dimFrame.midY)
        }
    }
}

extension GiftStatsValueTileView {
    func morphLook(in card: UIView) -> GiftMorphLook {
        return self.flat.morphLook(in: card)
    }

    func morphThing(in card: UIView, isFrozen: Bool) -> GiftMorphThing {
        let wrapper = UIView(frame: CGRect(origin: .zero, size: self.bounds.size))
        wrapper.isUserInteractionEnabled = false
        let frame = self.convert(self.bounds, to: card)
        return GiftMorphThing(
            view: wrapper,
            home: { [weak self] in
                return isFrozen ? frame : (self?.convert(self?.bounds ?? .zero, to: card) ?? frame)
            },
            activate: { [weak self] in
                guard let self else {
                    return
                }
                wrapper.addSubview(self.label)
                wrapper.addSubview(self.dim)
                wrapper.addSubview(self.value)
                wrapper.addSubview(self.glyph)
            },
            release: { [weak self] in
                guard let self else {
                    return
                }
                self.flat.addSubview(self.label)
                self.flat.addSubview(self.dim)
                self.flat.addSubview(self.value)
                self.flat.addSubview(self.glyph)
            }
        )
    }
}
