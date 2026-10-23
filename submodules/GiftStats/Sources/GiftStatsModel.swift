import Foundation
import TelegramCore

public enum GiftStatsScope: Equatable, Hashable {
    case collection
    /// The model is identified by the id of its sticker file.
    case model(fileId: Int64)
}

/// Prices are in US cents.
public struct GiftStatsSummary: Equatable {
    /// Lowest fixed-price listing; when nil the client uses the last point of the price graph.
    public var floorPrice: Int64?
    /// Issued count of the collection, or of the gifts with the model.
    public var supply: Int32
    public var listedCount: Int32

    public init(floorPrice: Int64?, supply: Int32, listedCount: Int32) {
        self.floorPrice = floorPrice
        self.supply = supply
        self.listedCount = listedCount
    }
}

/// The server sends the market as a string; unknown names are kept as `.other`.
public enum GiftSaleMarket: Equatable, Hashable {
    case telegram
    case fragment
    case portals
    case mrkt
    case tonnel
    case other(String)

    public var title: String {
        switch self {
        case .telegram:
            return "Telegram"
        case .fragment:
            return "Fragment"
        case .portals:
            return "Portals"
        case .mrkt:
            return "MRKT"
        case .tonnel:
            return "Tonnel"
        case let .other(name):
            return name
        }
    }

    public init(name: String) {
        switch name.lowercased() {
        case "telegram":
            self = .telegram
        case "fragment":
            self = .fragment
        case "portals":
            self = .portals
        case "mrkt":
            self = .mrkt
        case "tonnel":
            self = .tonnel
        default:
            self = .other(name)
        }
    }
}

/// RGB colors as in the backdrop attribute: center and edge.
public struct GiftSaleBackdrop: Equatable {
    public var innerColor: Int32
    public var outerColor: Int32

    public init(innerColor: Int32, outerColor: Int32) {
        self.innerColor = innerColor
        self.outerColor = outerColor
    }
}

/// `priceUsd` is in US cents.
public struct GiftSale: Equatable {
    public var number: Int32
    public var modelName: String
    public var modelFile: TelegramMediaFile?
    public var backdrop: GiftSaleBackdrop?
    /// Opened on tap; nil makes the row inactive.
    public var gift: StarGift.UniqueGift?
    public var market: GiftSaleMarket
    public var priceUsd: Int64
    public var date: Int32

    public init(number: Int32, modelName: String, modelFile: TelegramMediaFile?, backdrop: GiftSaleBackdrop? = nil, gift: StarGift.UniqueGift? = nil, market: GiftSaleMarket, priceUsd: Int64, date: Int32) {
        self.number = number
        self.modelName = modelName
        self.modelFile = modelFile
        self.backdrop = backdrop
        self.gift = gift
        self.market = market
        self.priceUsd = priceUsd
        self.date = date
    }
}

/// `count` is the total number of sales in the log.
public struct GiftSalesPage: Equatable {
    public var sales: [GiftSale]
    public var count: Int32

    public init(sales: [GiftSale], count: Int32) {
        self.sales = sales
        self.count = count
    }
}

/// Graphs use the regular stats chart JSON. Price: x in milliseconds, y in US cents. Sales: one series, sales per day.
public struct GiftStats: Equatable {
    public static let salesPageSize: Int32 = 20

    public var priceGraph: StatsGraph
    public var salesGraph: StatsGraph
    public var summary: GiftStatsSummary
    /// First page of fixed-price sales, newest first; the rest comes from `GiftStatsProvider.recentSales`.
    public var recentSales: [GiftSale]

    public init(priceGraph: StatsGraph, salesGraph: StatsGraph, summary: GiftStatsSummary, recentSales: [GiftSale] = []) {
        self.priceGraph = priceGraph
        self.salesGraph = salesGraph
        self.summary = summary
        self.recentSales = recentSales
    }
}

public struct GiftStatsPriceSeries: Equatable {
    /// Unix time in seconds.
    public let times: [Double]
    /// First series, US cents.
    public let values: [Double]
    public let allValues: [[Double]]

    public init?(graph: StatsGraph) {
        guard case let .Loaded(_, data) = graph, let jsonData = data.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any],
              let columns = object["columns"] as? [[Any]], let types = object["types"] as? [String: String] else {
            return nil
        }
        var times: [Double]?
        var values: [Double]?
        var all: [[Double]] = []
        for column in columns {
            guard let id = column.first as? String, let type = types[id] else {
                continue
            }
            let numbers = column.dropFirst().compactMap { ($0 as? NSNumber)?.doubleValue }
            if type == "x" {
                times = numbers.map { $0 > 100_000_000_000 ? $0 / 1000.0 : $0 }
            } else {
                all.append(numbers)
                if values == nil {
                    values = numbers
                }
            }
        }
        // Interpolation indexes all series by point, so every series must be complete and finite.
        guard let times, let values, times.count == values.count, times.count > 1, all.allSatisfy({ $0.count == times.count && $0.allSatisfy({ $0.isFinite }) }), times.allSatisfy({ $0.isFinite }) else {
            return nil
        }
        self.times = times
        self.values = values
        self.allValues = all
    }

    public func interpolatedValue(at time: Double, series: Int) -> Double {
        guard series < self.allValues.count else {
            return 0.0
        }
        let values = self.allValues[series]
        guard let first = self.times.first, let last = self.times.last else {
            return 0.0
        }
        if time <= first {
            return values[0]
        }
        if time >= last {
            return values[values.count - 1]
        }
        var low = 0
        var high = self.times.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if self.times[mid] <= time {
                low = mid
            } else {
                high = mid
            }
        }
        let span = self.times[high] - self.times[low]
        let fraction = span > 0.0 ? (time - self.times[low]) / span : 0.0
        return values[low] + (values[high] - values[low]) * fraction
    }
}
