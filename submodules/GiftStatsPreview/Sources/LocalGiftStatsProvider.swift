import Foundation
import SwiftSignalKit
import TelegramCore
import GiftStats

/// Preview stand-in for the stats server: a deterministic year of data seeded by the gift name.
/// The level comes from the collection's lowest fixed-price listing (or its supply), scaled by model rarity.
public final class LocalGiftStatsProvider: GiftStatsProvider {
    /// Data a real server would have on its own, keyed by gift id. Both signals complete after one value.
    public struct Sources {
        public var market: (Int64) -> Signal<GiftStatsMarket, NoError>
        /// Empty lists when they could not be loaded.
        public var models: (Int64) -> Signal<GiftStatsVariants, NoError>

        public init(market: @escaping (Int64) -> Signal<GiftStatsMarket, NoError>, models: @escaping (Int64) -> Signal<GiftStatsVariants, NoError>) {
            self.market = market
            self.models = models
        }
    }

    private static let secondsInDay = 86400.0
    private let sources: Sources
    private let lock = NSLock()
    private var cache: [String: GiftStats] = [:]
    private var salesCache: [String: [GiftSale]] = [:]
    private var latestSalesKey: [String: String] = [:]
    /// Simulated network latency.
    private static let pageDelay = 0.4
    private static let salesCount = 150

    public init(sources: Sources) {
        self.sources = sources
    }

    public var isAvailable: Bool {
        return true
    }

    public func stats(for gift: StarGift.UniqueGift, scope: GiftStatsScope) -> Signal<GiftStats?, NoError> {
        return self.sources.market(gift.giftId)
        |> take(1)
        |> mapToSignal { [weak self] market -> Signal<GiftStats?, NoError> in
            guard let self else {
                return .single(nil)
            }
            return self.stats(gift: gift, scope: scope, market: market)
        }
    }

    private func stats(gift: StarGift.UniqueGift, scope: GiftStatsScope, market: GiftStatsMarket) -> Signal<GiftStats?, NoError> {
        // The catalog can arrive after the first request, so the market is part of the key.
        let marketKey = "\(market.collectionFloorStars ?? 0)|\(market.usdCentsPerStar)"
        let baseKey = LocalGiftStatsProvider.salesKey(gift: gift, scope: scope)
        let key = baseKey + "|" + marketKey
        self.lock.lock()
        let cached = self.cache[key]
        if cached != nil {
            self.latestSalesKey[baseKey] = key
        }
        self.lock.unlock()
        if let cached {
            return .single(cached)
        }
        let own = LocalGiftStatsProvider.modelInfo(of: gift)
        let ownBackdrop = LocalGiftStatsProvider.backdropInfo(of: gift)
        let finish: (GiftStatsVariants) -> GiftStats = { [weak self] variants in
            let models = variants.models
            let backdrops = variants.backdrops.isEmpty ? (ownBackdrop.map { [$0] } ?? []) : variants.backdrops
            let symbols = variants.symbols.isEmpty ? gift.attributes.filter { $0.attributeType == .pattern } : variants.symbols
            let result = LocalGiftStatsProvider.makeStats(gift: gift, scope: scope, key: key, market: market, models: models, own: own, backdrops: backdrops, symbols: symbols, owners: variants.owners)
            if let self {
                self.lock.lock()
                // Don't cache a collection result built without its models; the next request retries.
                if !models.isEmpty || scope != .collection {
                    self.cache[key] = result.stats
                }
                self.salesCache[key] = result.sales
                self.latestSalesKey[baseKey] = key
                self.lock.unlock()
            }
            return result.stats
        }
        if case .collection = scope {
            return self.sources.models(gift.giftId)
            |> take(1)
            |> map { variants -> GiftStats? in
                return finish(variants)
            }
        }
        return .single(finish(GiftStatsVariants(models: own.map { [$0] } ?? [], backdrops: [])))
    }

    public func recentSales(for gift: StarGift.UniqueGift, scope: GiftStatsScope, offset: Int32, limit: Int32) -> Signal<GiftSalesPage?, NoError> {
        // Pages come from the log built by `stats`, which is always requested first.
        self.lock.lock()
        let sales = self.latestSalesKey[LocalGiftStatsProvider.salesKey(gift: gift, scope: scope)].flatMap { self.salesCache[$0] }
        self.lock.unlock()
        guard let sales else {
            return .single(nil)
        }
        let start = min(sales.count, max(0, Int(offset)))
        let end = min(sales.count, start + max(0, Int(limit)))
        let page = GiftSalesPage(sales: Array(sales[start ..< end]), count: Int32(sales.count))
        return .single(page) |> delay(LocalGiftStatsProvider.pageDelay, queue: Queue.mainQueue())
    }

    private static func modelInfo(of gift: StarGift.UniqueGift) -> GiftStatsModelInfo? {
        for attribute in gift.attributes {
            if case let .model(name, file, rarity, _) = attribute {
                return GiftStatsModelInfo(name: name, file: file, rarity: rarity)
            }
        }
        return nil
    }

    private static func backdropInfo(of gift: StarGift.UniqueGift) -> GiftStatsBackdropInfo? {
        for attribute in gift.attributes {
            if case let .backdrop(_, _, innerColor, outerColor, _, _, rarity) = attribute {
                return GiftStatsBackdropInfo(backdrop: GiftSaleBackdrop(innerColor: innerColor, outerColor: outerColor), rarity: rarity, attribute: attribute)
            }
        }
        return nil
    }

    private static func salesKey(gift: StarGift.UniqueGift, scope: GiftStatsScope) -> String {
        switch scope {
        case .collection:
            return "\(gift.title)|collection"
        case let .model(fileId):
            return "\(gift.title)|model|\(fileId)"
        }
    }

    /// Multiplier over the collection floor: ~1.05 for common models, up to 3.5 for the rarest.
    private static func modelFactor(rarity: StarGift.UniqueGift.Attribute.Rarity) -> Double {
        switch rarity {
        case let .permille(value):
            return min(3.5, max(1.05, 1.25 * pow(20.0 / Double(max(1, value)), 0.38)))
        case .uncommon:
            return 1.2
        case .rare:
            return 1.7
        case .epic:
            return 2.4
        case .legendary:
            return 3.5
        }
    }

    /// Floor in US cents for a collection without listings: $100 at 50k supply, higher for smaller supply, at least $2.
    private static func supplyLevel(total: Int32) -> Double {
        let supply = Double(total > 0 ? total : 1_000_000)
        return min(20_000_000.0, max(200.0, 10_000.0 * pow(50_000.0 / supply, 1.3)))
    }

    private static func makeStats(gift: StarGift.UniqueGift, scope: GiftStatsScope, key: String, market: GiftStatsMarket, models: [GiftStatsModelInfo], own: GiftStatsModelInfo?, backdrops: [GiftStatsBackdropInfo], symbols: [StarGift.UniqueGift.Attribute], owners: [EnginePeer.Id]) -> (stats: GiftStats, sales: [GiftSale]) {
        let model = own
        let factor = model.map { modelFactor(rarity: $0.rarity) } ?? 1.0
        let seedBase = GiftStatsGenerator.seed(for: gift.title)
        var generator = GiftStatsGenerator(seed: seedBase)
        let spread = 0.75 + 0.5 * generator.unit()
        let collectionFloor: Double
        if let floorStars = market.collectionFloorStars, floorStars > 0 {
            collectionFloor = Double(floorStars) * market.usdCentsPerStar
        } else {
            collectionFloor = supplyLevel(total: gift.availability.total) * spread
        }
        let collectionVolume = 40.0 + generator.unit() * 260.0

        let lastFloor: Double
        let volume: Double
        let listed: Double
        let supply: Double
        switch scope {
        case .collection:
            lastFloor = collectionFloor
            volume = collectionVolume
            listed = max(3.0, collectionVolume * 0.7)
            supply = Double(gift.availability.issued)
        case .model:
            lastFloor = collectionFloor * factor
            let share = model.map { max(0.004, Double($0.rarity.permilleValue) / 1000.0) } ?? 0.04
            volume = max(1.2, collectionVolume * share * 1.6)
            listed = max(1.0, (collectionVolume * share * 1.1).rounded())
            // Estimated from rarity; the server sends the exact number.
            supply = (Double(gift.availability.issued) * Double(model.map { $0.rarity.permilleValue } ?? 0) / 1000.0).rounded()
        }
        let shape = GiftStatsShape(seed: GiftStatsGenerator.seed(for: key), lastFloor: lastFloor, volume: volume)

        let now = Date().timeIntervalSince1970
        let today = floor(now / secondsInDay) * secondsInDay
        let count = GiftStatsShape.dayCount
        let times = (0 ..< count).map { today - Double(count - 1 - $0) * secondsInDay }

        let lastFloorCents = Int64(saturating: shape.floor[count - 1])
        let summary = GiftStatsSummary(
            floorPrice: lastFloorCents,
            supply: Int32(saturating: supply),
            listedCount: Int32(saturating: listed.rounded())
        )

        let priceGraph = chartJson(times: times, series: [
            (id: "y0", type: "line", name: "Floor", color: "#3497ED", values: shape.floor)
        ])
        let salesGraph = chartJson(times: times, series: [
            (id: "y0", type: "bar", name: "Sales", color: "#34C759", values: shape.sales)
        ])
        let sales = makeSales(template: gift, scope: scope, key: key, models: models, own: own, backdrops: backdrops, symbols: symbols, owners: owners, issued: Double(gift.availability.issued), collectionFloor: collectionFloor, now: now, count: LocalGiftStatsProvider.salesCount)
        let firstPage = Array(sales.prefix(Int(GiftStats.salesPageSize)))
        return (GiftStats(priceGraph: .Loaded(token: nil, data: priceGraph), salesGraph: .Loaded(token: nil, data: salesGraph), summary: summary, recentSales: firstPage), sales)
    }

    private static func makeSales(template: StarGift.UniqueGift, scope: GiftStatsScope, key: String, models: [GiftStatsModelInfo], own: GiftStatsModelInfo?, backdrops: [GiftStatsBackdropInfo], symbols: [StarGift.UniqueGift.Attribute], owners: [EnginePeer.Id], issued gifts: Double, collectionFloor: Double, now: Double, count: Int) -> [GiftSale] {
        var pool = models.isEmpty ? (own.map { [$0] } ?? []) : models
        if case let .model(fileId) = scope {
            pool = pool.filter { $0.file.fileId.id == fileId }
            if pool.isEmpty, let own {
                pool = [own]
            }
        }
        guard !pool.isEmpty else {
            return []
        }
        var generator = GiftStatsGenerator(seed: GiftStatsGenerator.seed(for: key + "|sales"))
        let backdropWeight = backdrops.reduce(0.0) { $0 + Double(max(1, $1.rarity.permilleValue)) }
        func pickBackdrop() -> GiftStatsBackdropInfo? {
            guard !backdrops.isEmpty else {
                return nil
            }
            var pick = generator.unit() * backdropWeight
            for item in backdrops {
                pick -= Double(max(1, item.rarity.permilleValue))
                if pick <= 0.0 {
                    return item
                }
            }
            return backdrops[backdrops.count - 1]
        }
        // "ResistanceDog-2024" -> "ResistanceDog"
        let slugBase = template.slug.range(of: "-", options: .backwards).map { String(template.slug[..<$0.lowerBound]) } ?? template.slug
        let markets: [(GiftSaleMarket, Double)] = [(.telegram, 0.32), (.fragment, 0.24), (.portals, 0.17), (.mrkt, 0.15), (.tonnel, 0.12)]
        let issued = max(10.0, gifts)
        let gapScale = pool.count == 1 ? 5.0 : 1.0
        var time = now
        var sales: [GiftSale] = []
        for _ in 0 ..< count {
            time -= (90.0 + 4200.0 * pow(generator.unit(), 2.0)) * gapScale
            let model = pool[Int(generator.unit() * Double(pool.count)) % pool.count]
            var pick = generator.unit()
            var market = markets[0].0
            for (candidate, weight) in markets {
                if pick < weight {
                    market = candidate
                    break
                }
                pick -= weight
            }
            let price = collectionFloor * modelFactor(rarity: model.rarity) * (0.92 + 0.75 * generator.unit())
            let number = Int32(saturating: 1.0 + generator.unit() * (issued - 1.0))
            let backdrop = pickBackdrop()
            let owner: StarGift.UniqueGift.Owner? = owners.isEmpty ? nil : .peerId(owners[Int(generator.unit() * Double(owners.count)) % owners.count])
            var attributes: [StarGift.UniqueGift.Attribute] = [.model(name: model.name, file: model.file, rarity: model.rarity, crafted: false)]
            if !symbols.isEmpty {
                attributes.append(symbols[Int(generator.unit() * Double(symbols.count)) % symbols.count])
            }
            if let attribute = backdrop?.attribute {
                attributes.append(attribute)
            }
            let soldGift = StarGift.UniqueGift(
                id: template.id ^ (Int64(number) &* 2654435761),
                giftId: template.giftId,
                title: template.title,
                number: number,
                slug: "\(slugBase)-\(number)",
                owner: owner,
                attributes: attributes,
                availability: template.availability,
                giftAddress: nil,
                resellAmounts: nil,
                resellForTonOnly: false,
                releasedBy: template.releasedBy,
                valueAmount: nil,
                valueCurrency: nil,
                valueUsdAmount: nil,
                flags: [],
                themePeerId: nil,
                peerColor: nil,
                hostPeerId: nil,
                minOfferStars: nil,
                craftChancePermille: nil
            )
            sales.append(GiftSale(
                number: number,
                modelName: model.name,
                modelFile: model.file,
                backdrop: backdrop?.backdrop,
                gift: soldGift,
                market: market,
                priceUsd: Int64(saturating: price.rounded()),
                date: Int32(saturating: time)
            ))
        }
        return sales
    }

    private static func chartJson(times: [Double], series: [(id: String, type: String, name: String, color: String, values: [Double])]) -> String {
        var xColumn: [Any] = ["x"]
        xColumn.append(contentsOf: times.map { Int64(saturating: $0 * 1000.0) })
        var columns: [[Any]] = [xColumn]
        var types: [String: String] = ["x": "x"]
        var names: [String: String] = [:]
        var colors: [String: String] = [:]
        for item in series {
            var column: [Any] = [item.id]
            column.append(contentsOf: item.values.map { Int64(saturating: $0) })
            columns.append(column)
            types[item.id] = item.type
            names[item.id] = item.name
            colors[item.id] = item.color
        }
        let object: [String: Any] = ["columns": columns, "types": types, "names": names, "colors": colors]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}
