import Foundation
import UIKit
import Display
import GiftStats

/// Mimics SwiftUI `.contentTransition(.numericText())`: only changed characters roll and blur, staggered by 15 ms.
/// Each digit is a piece and runs of other characters stay whole to keep their shaping. The caller positions the view.
final class GiftStatsNumericTextView: UIView {
    enum Direction {
        case up
        case down
    }

    static let duration: Double = 0.35
    private static let stagger: Double = 0.015
    private static let lift: CGFloat = 0.4

    private(set) var text: String?
    private var font: UIFont?
    private var color: UIColor?
    private var pieces: [GiftStatsNumericPiece] = []

    /// VoiceOver label overriding `text`.
    var spoken: String?

    override var accessibilityLabel: String? {
        get {
            return self.spoken ?? self.text
        }
        set {
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.isAccessibilityElement = true
        self.accessibilityTraits = .staticText
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func lineHeight(of font: UIFont) -> CGFloat {
        return ceil(font.lineHeight)
    }

    static func width(of text: String, font: UIFont) -> CGFloat {
        return ceil(split(text).reduce(0.0) { $0 + GiftStatsNumericPiece.advance(of: $1, font: font) })
    }

    /// Runs `changes` with the same spring as the digits.
    static func move(animated: Bool, _ changes: @escaping () -> Void) {
        if animated && !GiftStatsEnvironment.reduceMotion {
            UIView.animate(withDuration: self.duration, delay: 0.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0.0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
        } else {
            changes()
        }
    }

    private static func split(_ text: String) -> [String] {
        var result: [String] = []
        var run = ""
        for character in text {
            if character.isASCII && character.isNumber {
                if !run.isEmpty {
                    result.append(run)
                    run = ""
                }
                result.append(String(character))
            } else {
                run.append(character)
            }
        }
        if !run.isEmpty {
            result.append(run)
        }
        return result
    }

    /// The user's number separators, used to parse texts and pick the roll direction. Set on layout.
    static var separators: (grouping: String, decimal: String) = (",", ".")

    /// The first number in a text ("1,164", "11.94", "~$1,564").
    private static func number(in text: String) -> Double? {
        let grouping = self.separators.grouping
        let decimal = self.separators.decimal
        var integer = ""
        var fraction = ""
        var isInFraction = false
        var hasStarted = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isNumber, let digit = character.wholeNumberValue, digit < 10 {
                hasStarted = true
                if isInFraction {
                    fraction += String(digit)
                } else {
                    integer += String(digit)
                }
                index = text.index(after: index)
                continue
            }
            if hasStarted {
                let rest = text[index...]
                if !isInFraction, !decimal.isEmpty, rest.hasPrefix(decimal) {
                    isInFraction = true
                    index = text.index(index, offsetBy: decimal.count)
                    continue
                }
                if !isInFraction, !grouping.isEmpty, rest.hasPrefix(grouping) {
                    index = text.index(index, offsetBy: grouping.count)
                    continue
                }
                break
            }
            index = text.index(after: index)
        }
        guard !integer.isEmpty else {
            return nil
        }
        return Double(integer + (fraction.isEmpty ? "" : "." + fraction))
    }

    private static func direction(from old: String, to new: String) -> Direction {
        if let before = self.number(in: old), let after = self.number(in: new), after < before {
            return .down
        }
        return .up
    }

    /// Without `direction` it is inferred from the numbers in the texts. Returns the text size.
    @discardableResult
    func update(text: String, font: UIFont, color: UIColor, animated: Bool, direction: Direction? = nil) -> CGSize {
        let strings = GiftStatsNumericTextView.split(text)
        let height = GiftStatsNumericTextView.lineHeight(of: font)
        var origins: [CGFloat] = []
        var widths: [CGFloat] = []
        var x: CGFloat = 0.0
        for string in strings {
            let width = GiftStatsNumericPiece.advance(of: string, font: font)
            origins.append(x)
            widths.append(width)
            x += width
        }
        let size = CGSize(width: ceil(x), height: height)

        let previousText = self.text
        let isRestyled = self.font != font || self.color != color
        self.text = text
        self.font = font
        self.color = color

        if previousText == text && !isRestyled {
            return size
        }
        guard let previousText, animated, !isRestyled, !GiftStatsEnvironment.reduceMotion else {
            self.rebuild(strings: strings, origins: origins, widths: widths, font: font, color: color, height: height)
            return size
        }

        let old = self.pieces
        let count = strings.count
        var prefix = 0
        while prefix < min(old.count, count) && old[prefix].text == strings[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < min(old.count, count) - prefix && old[old.count - 1 - suffix].text == strings[count - 1 - suffix] {
            suffix += 1
        }
        var current: [GiftStatsNumericPiece?] = Array(repeating: nil, count: count)
        for index in 0 ..< prefix {
            current[index] = old[index]
        }
        for offset in 0 ..< suffix {
            current[count - 1 - offset] = old[old.count - 1 - offset]
        }
        // Match the middle from the right so digits keep their place value when the length changes.
        let oldEnd = old.count - suffix
        let newEnd = count - suffix
        var changes: [(leaving: GiftStatsNumericPiece?, entering: Int?)] = []
        for offset in stride(from: max(oldEnd, newEnd) - prefix - 1, through: 0, by: -1) {
            let oldIndex = oldEnd - 1 - offset
            let newIndex = newEnd - 1 - offset
            let hasOld = oldIndex >= prefix
            let hasNew = newIndex >= prefix
            if hasOld && hasNew && old[oldIndex].text == strings[newIndex] {
                current[newIndex] = old[oldIndex]
            } else {
                changes.append((hasOld ? old[oldIndex] : nil, hasNew ? newIndex : nil))
            }
        }

        let sign: CGFloat = (direction ?? GiftStatsNumericTextView.direction(from: previousText, to: text)) == .up ? -1.0 : 1.0
        let lift = ceil(height * GiftStatsNumericTextView.lift)
        var pieces: [GiftStatsNumericPiece] = []
        for index in 0 ..< count {
            if let piece = current[index] {
                pieces.append(piece)
            } else {
                let piece = GiftStatsNumericPiece(text: strings[index], font: font, color: color, width: widths[index], height: height)
                piece.place(x: origins[index])
                self.addSubview(piece)
                pieces.append(piece)
                current[index] = piece
            }
        }
        for (order, change) in changes.enumerated() {
            let delay = Double(order) * GiftStatsNumericTextView.stagger
            if let leaving = change.leaving {
                self.animateOut(leaving, toX: change.entering.map { origins[$0] + widths[$0] / 2.0 }, shift: sign * lift, delay: delay)
            }
            if let index = change.entering, let piece = current[index] {
                self.animateIn(piece, font: font, color: color, shift: -sign * lift, delay: delay)
            }
        }
        let placed = current
        GiftStatsNumericTextView.move(animated: true) {
            for (index, piece) in pieces.enumerated() where placed[index] === piece && old.contains(where: { $0 === piece }) {
                piece.place(x: origins[index])
            }
        }
        self.pieces = pieces
        return size
    }

    private func rebuild(strings: [String], origins: [CGFloat], widths: [CGFloat], font: UIFont, color: UIColor, height: CGFloat) {
        for subview in self.subviews {
            subview.removeFromSuperview()
        }
        self.pieces = strings.enumerated().map { index, string in
            let piece = GiftStatsNumericPiece(text: string, font: font, color: color, width: widths[index], height: height)
            piece.place(x: origins[index])
            self.addSubview(piece)
            return piece
        }
    }

    private func animate(delay: Double, _ changes: @escaping () -> Void, completion: ((Bool) -> Void)?) {
        UIView.animate(withDuration: GiftStatsNumericTextView.duration, delay: delay, usingSpringWithDamping: 1.0, initialSpringVelocity: 0.0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes, completion: completion)
    }

    private func animateOut(_ piece: GiftStatsNumericPiece, toX centre: CGFloat?, shift: CGFloat, delay: Double) {
        guard let font = self.font, let color = self.color else {
            piece.removeFromSuperview()
            return
        }
        let blur = piece.blur(font: font, color: color)
        blur.alpha = 0.0
        self.animate(delay: delay, {
            piece.content.transform = CGAffineTransform(translationX: 0.0, y: shift)
            piece.content.alpha = 0.0
            piece.label.alpha = 0.0
            blur.alpha = 1.0
            if let centre {
                piece.center = CGPoint(x: centre, y: piece.center.y)
            }
        }, completion: { _ in
            piece.removeFromSuperview()
        })
    }

    private func animateIn(_ piece: GiftStatsNumericPiece, font: UIFont, color: UIColor, shift: CGFloat, delay: Double) {
        let blur = piece.blur(font: font, color: color)
        blur.alpha = 1.0
        piece.content.transform = CGAffineTransform(translationX: 0.0, y: shift)
        piece.content.alpha = 0.0
        piece.label.alpha = 0.0
        self.animate(delay: delay, {
            piece.content.transform = .identity
            piece.content.alpha = 1.0
            piece.label.alpha = 1.0
            blur.alpha = 0.0
        }, completion: { _ in
            piece.dropBlur()
        })
    }
}
