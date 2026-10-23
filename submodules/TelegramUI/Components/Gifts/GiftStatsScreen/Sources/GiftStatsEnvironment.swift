import Foundation
import UIKit
import TelegramPresentationData

enum GiftStatsEnvironment {
    static var reduceMotion: Bool {
        return UIAccessibility.isReduceMotionEnabled
    }

    static var reduceTransparency: Bool {
        return UIAccessibility.isReduceTransparencyEnabled
    }

    static var increaseContrast: Bool {
        return UIAccessibility.isDarkerSystemColorsEnabled
    }

    /// The app layout is never mirrored by the system, so the stats lay out RTL text and columns themselves.
    static func isRTL(strings: PresentationStrings) -> Bool {
        return NSLocale.characterDirection(forLanguage: strings.baseLanguageCode) == .rightToLeft
    }
}

