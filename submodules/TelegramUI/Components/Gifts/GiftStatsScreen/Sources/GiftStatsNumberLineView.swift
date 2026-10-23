import Foundation
import UIKit
import Display

/// A text line with one animated number, e.g. "Buy from 697".
final class GiftStatsNumberLineView: UIView {
    struct Content: Equatable {
        var prefix: String
        var value: String
        var suffix: String
        /// Gram glyph before the number.
        var hasGlyph: Bool = false
        /// VoiceOver label; nil reads `text`.
        var spoken: String?
        var isRTL: Bool = false

        var text: String {
            return self.prefix + self.value + self.suffix
        }
    }

    private let prefixText = GiftStatsNumericTextView()
    private let valueText = GiftStatsNumericTextView()
    private let suffixText = GiftStatsNumericTextView()
    private let glyph = GiftStatsGram.make()
    private var content: Content?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.isAccessibilityElement = true
        self.accessibilityTraits = .staticText
        self.addSubview(self.prefixText)
        self.addSubview(self.valueText)
        self.addSubview(self.suffixText)
        self.addSubview(self.glyph)
        self.glyph.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func cleanPrefix(_ content: Content) -> String {
        return content.hasGlyph ? content.prefix.trimmingCharacters(in: .whitespaces) : content.prefix
    }

    private static func glyphRoom(content: Content, font: UIFont) -> CGFloat {
        return content.hasGlyph ? GiftStatsGram.side(fontSize: font.pointSize) + GiftStatsGram.gap(fontSize: font.pointSize) * 2.0 : 0.0
    }

    static func size(content: Content, font: UIFont) -> CGSize {
        let prefix = cleanPrefix(content)
        let width = GiftStatsNumericTextView.width(of: prefix, font: font) + GiftStatsNumberLineView.glyphRoom(content: content, font: font)
            + GiftStatsNumericTextView.width(of: content.value, font: font) + GiftStatsNumericTextView.width(of: content.suffix, font: font)
        return CGSize(width: width, height: GiftStatsNumericTextView.lineHeight(of: font))
    }

    /// The caller sets the size from `size(content:font:)`. The first update is never animated.
    func update(content: Content, font: UIFont, color: UIColor, animated: Bool) {
        let isAnimated = animated && self.content != nil
        self.content = content
        let height = GiftStatsNumericTextView.lineHeight(of: font)
        let prefix = GiftStatsNumberLineView.cleanPrefix(content)
        let sizes = [
            self.prefixText.update(text: prefix, font: font, color: color, animated: isAnimated),
            self.valueText.update(text: content.value, font: font, color: color, animated: isAnimated),
            self.suffixText.update(text: content.suffix, font: font, color: color, animated: isAnimated)
        ]
        let side = GiftStatsGram.side(fontSize: font.pointSize)
        let gap = content.hasGlyph ? GiftStatsGram.gap(fontSize: font.pointSize) : 0.0
        let wasHidden = self.glyph.isHidden
        self.glyph.isHidden = !content.hasGlyph
        self.glyph.color = color
        self.accessibilityLabel = content.spoken ?? content.text
        let glyphY = floor((height - side) / 2.0)
        let glyphFrame: CGRect
        let frames: [CGRect]
        if content.isRTL {
            // Left to right: suffix, value, glyph, prefix.
            let valueX = sizes[2].width
            glyphFrame = CGRect(x: valueX + sizes[1].width + gap, y: glyphY, width: side, height: side)
            frames = [
                CGRect(x: valueX + sizes[1].width + gap + side + gap, y: 0.0, width: sizes[0].width, height: height),
                CGRect(x: valueX, y: 0.0, width: sizes[1].width, height: height),
                CGRect(x: 0.0, y: 0.0, width: sizes[2].width, height: height)
            ]
        } else {
            glyphFrame = CGRect(x: sizes[0].width + gap, y: glyphY, width: side, height: side)
            let x = sizes[0].width + gap + side + gap
            frames = [
                CGRect(x: 0.0, y: 0.0, width: sizes[0].width, height: height),
                CGRect(x: x, y: 0.0, width: sizes[1].width, height: height),
                CGRect(x: x + sizes[1].width, y: 0.0, width: sizes[2].width, height: height)
            ]
        }
        if wasHidden {
            self.glyph.frame = glyphFrame
        }
        let views = [self.prefixText, self.valueText, self.suffixText]
        GiftStatsNumericTextView.move(animated: isAnimated) {
            self.glyph.frame = glyphFrame
            for (view, frame) in zip(views, frames) {
                view.bounds = CGRect(origin: .zero, size: frame.size)
                view.center = CGPoint(x: frame.midX, y: frame.midY)
            }
        }
    }
}
