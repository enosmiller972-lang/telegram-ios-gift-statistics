import Foundation
import UIKit
import Display
import AppBundle
import AccountContext
import TelegramPresentationData
import TelegramStringFormatting
import GiftStats

/// Prices arrive in US cents and are shown in Gram, converted with the app config `ton_usd_rate` (USD per Gram).
public struct GiftStatsMoney: Equatable {
    private static let fallbackUsdPerGram: Double = 3.5

    public let usdPerGram: Double

    public init(usdPerGram: Double) {
        self.usdPerGram = usdPerGram > 0.0 && usdPerGram.isFinite ? usdPerGram : GiftStatsMoney.fallbackUsdPerGram
    }

    public init(context: AccountContext) {
        let rate = context.currentAppConfiguration.with({ $0 }).data?["ton_usd_rate"] as? Double
        self.init(usdPerGram: rate ?? GiftStatsMoney.fallbackUsdPerGram)
    }

    /// Whole Gram from 100 up ("462"), two decimals below ("11.94"). No currency sign.
    public func gram(cents: Int64, dateTimeFormat: PresentationDateTimeFormat) -> String {
        return formatTonAmountText(self.roundedNano(cents: cents), dateTimeFormat: dateTimeFormat, maxDecimalPositions: 2)
    }

    /// For VoiceOver: "462 Grams".
    public func spokenGram(cents: Int64, dateTimeFormat: PresentationDateTimeFormat, strings: PresentationStrings) -> String {
        return formatTonAmountText(self.roundedNano(cents: cents), dateTimeFormat: dateTimeFormat, maxDecimalPositions: 2, formatString: strings.Currency_Grams)
    }

    private func roundedNano(cents: Int64) -> Int64 {
        let value = Double(cents) / 100.0 / self.usdPerGram
        let rounded = value >= 100.0 ? value.rounded() : (value * 100.0).rounded() / 100.0
        return Int64(saturating: (rounded * 1_000_000_000.0).rounded())
    }

    /// "~$1,617".
    public func usd(cents: Int64, dateTimeFormat: PresentationDateTimeFormat) -> String {
        return "~" + GiftStatsFormat.price(cents, dateTimeFormat: dateTimeFormat)
    }

    /// Converts chart values in US cents to Gram.
    public var chartDivisor: Double {
        return 100.0 * self.usdPerGram
    }
}

public enum GiftStatsGram {
    private static var cache: [UInt32: UIImage] = [:]

    /// Pre-tinted rather than a template image, so snapshots keep the colour.
    static func image(color: UIColor) -> UIImage? {
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        // Wide-gamut components can fall outside 0...1.
        func byte(_ component: CGFloat) -> UInt32 {
            return component.isFinite ? UInt32(max(0.0, min(255.0, (component * 255.0).rounded()))) : 0
        }
        let key = byte(red) << 24 | byte(green) << 16 | byte(blue) << 8 | byte(alpha)
        if let image = self.cache[key] {
            return image
        }
        guard let image = generateTintedImage(image: UIImage(bundleImageName: "Ads/TonMedium"), color: color) else {
            return nil
        }
        self.cache[key] = image
        return image
    }

    static func side(fontSize: CGFloat) -> CGFloat {
        return round(fontSize * 0.78)
    }

    static func gap(fontSize: CGFloat) -> CGFloat {
        return round(fontSize * 0.2)
    }

    final class View: UIImageView {
        var color: UIColor = .white {
            didSet {
                self.image = GiftStatsGram.image(color: self.color)
            }
        }

        init() {
            super.init(image: GiftStatsGram.image(color: .white))
            self.contentMode = .scaleAspectFit
            self.isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    static func make() -> View {
        return View()
    }

    public static func attachment(fontSize: CGFloat, color: UIColor) -> NSAttributedString {
        let attachment = NSTextAttachment()
        let side = GiftStatsGram.side(fontSize: fontSize)
        attachment.image = GiftStatsGram.image(color: color)
        attachment.bounds = CGRect(x: 0.0, y: -round(side * 0.1), width: side, height: side)
        return NSAttributedString(attachment: attachment)
    }
}
