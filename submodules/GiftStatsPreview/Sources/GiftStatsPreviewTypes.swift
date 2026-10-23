import Foundation
import TelegramCore
import GiftStats

/// Fixed-price market only; the gift value sent with a gift is not used because it includes auction sales.
public struct GiftStatsMarket: Equatable {
    /// `availability.minResaleStars`; nil when nothing is listed or the collection is not in the catalog.
    public var collectionFloorStars: Int64?
    /// Withdrawal rate from the app configuration.
    public var usdCentsPerStar: Double

    public init(collectionFloorStars: Int64?, usdCentsPerStar: Double) {
        self.collectionFloorStars = collectionFloorStars
        self.usdCentsPerStar = usdCentsPerStar
    }
}

public struct GiftStatsModelInfo: Equatable {
    public var name: String
    public var file: TelegramMediaFile
    public var rarity: StarGift.UniqueGift.Attribute.Rarity

    public init(name: String, file: TelegramMediaFile, rarity: StarGift.UniqueGift.Attribute.Rarity) {
        self.name = name
        self.file = file
        self.rarity = rarity
    }
}

public struct GiftStatsBackdropInfo: Equatable {
    public var backdrop: GiftSaleBackdrop
    public var rarity: StarGift.UniqueGift.Attribute.Rarity
    public var attribute: StarGift.UniqueGift.Attribute?

    public init(backdrop: GiftSaleBackdrop, rarity: StarGift.UniqueGift.Attribute.Rarity, attribute: StarGift.UniqueGift.Attribute? = nil) {
        self.backdrop = backdrop
        self.rarity = rarity
        self.attribute = attribute
    }
}

public struct GiftStatsVariants: Equatable {
    public var models: [GiftStatsModelInfo]
    public var backdrops: [GiftStatsBackdropInfo]
    public var symbols: [StarGift.UniqueGift.Attribute]
    /// Known peers used as current owners of sold gifts; empty means no owner is shown.
    public var owners: [EnginePeer.Id]

    public init(models: [GiftStatsModelInfo], backdrops: [GiftStatsBackdropInfo], symbols: [StarGift.UniqueGift.Attribute] = [], owners: [EnginePeer.Id] = []) {
        self.models = models
        self.backdrops = backdrops
        self.symbols = symbols
        self.owners = owners
    }
}
