import Foundation
import UIKit
import TelegramCore
import TelegramPresentationData

/// Always the dark theme, whatever the app theme, since the sheet sits on the gift's coloured backdrop.
enum GiftStatsLook {
    static let theme: PresentationTheme = makeDefaultDarkPresentationTheme(preview: false)

    static let textColor = UIColor.white
    static let secondaryTextColor = UIColor(white: 1.0, alpha: 0.62)

}
