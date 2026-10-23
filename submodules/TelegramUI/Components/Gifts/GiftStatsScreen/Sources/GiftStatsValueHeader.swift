import Foundation
import UIKit
import TelegramCore

/// Represents the gift's estimated valuation in US cents from Telegram's value info.
public struct GiftStatsValueHeader: Equatable {
    /// Value in US cents.
    public let usdCents: Int64

    public init(usdCents: Int64) {
        self.usdCents = usdCents
    }

    /// Derives the value header from `ValueInfo` or fallback USD amount.
    public static func make(gift: StarGift.UniqueGift, info: StarGift.UniqueGift.ValueInfo?) -> GiftStatsValueHeader? {
        guard gift.valueAmount != nil, let info, info.value > 0 else {
            return nil
        }
        if info.currency.uppercased() == "USD" {
            return GiftStatsValueHeader(usdCents: info.value)
        } else if let dollars = gift.valueUsdAmount, dollars > 0 {
            return GiftStatsValueHeader(usdCents: dollars)
        }
        return nil
    }
}
