import Foundation
import SwiftSignalKit
import TelegramCore

/// Server protocol and units (fixed-price market only, US cents) are described in `PROTOCOL.md`.
public protocol GiftStatsProvider: AnyObject {
    /// When false, the screens hide all statistics.
    var isAvailable: Bool { get }

    /// Only `gift.slug` and the model id are needed by a server implementation.
    func stats(for gift: StarGift.UniqueGift, scope: GiftStatsScope) -> Signal<GiftStats?, NoError>

    /// Newest first (`getStarGiftSales` in `PROTOCOL.md`). nil on failure; the list retries on the next scroll to the end.
    func recentSales(for gift: StarGift.UniqueGift, scope: GiftStatsScope, offset: Int32, limit: Int32) -> Signal<GiftSalesPage?, NoError>
}

public final class UnavailableGiftStatsProvider: GiftStatsProvider {
    public init() {
    }

    public var isAvailable: Bool {
        return false
    }

    public func stats(for gift: StarGift.UniqueGift, scope: GiftStatsScope) -> Signal<GiftStats?, NoError> {
        return .single(nil)
    }

    public func recentSales(for gift: StarGift.UniqueGift, scope: GiftStatsScope, offset: Int32, limit: Int32) -> Signal<GiftSalesPage?, NoError> {
        return .single(nil)
    }
}
