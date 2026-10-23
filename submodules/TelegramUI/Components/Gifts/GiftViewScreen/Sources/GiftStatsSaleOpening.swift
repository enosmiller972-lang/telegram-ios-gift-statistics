import Foundation
import UIKit
import Display
import TelegramCore
import TelegramPresentationData
import AccountContext
import GiftStats
import GiftStatsScreen
import SwiftSignalKit

/// Opens sold gifts (paging through the loaded sales) and the user's own gift in `GiftSaleMiniCardController`.
enum GiftStatsSaleOpening {
    static func open(context: AccountContext, from: ViewController, sales: [GiftSale], index: Int, source: UIView?) {
        guard index < sales.count, sales[index].gift != nil else {
            return
        }
        let strings = context.sharedContext.currentPresentationData.with { $0 }.strings
        var entries: [GiftMiniCardEntry] = []
        var position = 0
        for (i, sale) in sales.enumerated() {
            guard let gift = sale.gift else {
                continue
            }
            if i == index {
                position = entries.count
            }
            entries.append(GiftMiniCardEntry(gift: gift, priceTitle: strings.Gift_Stats_Sold, priceCents: sale.priceUsd))
        }
        self.present(context: context, from: from, entries: entries, index: position, source: source)
    }

    static func openOwn(context: AccountContext, from: ViewController, gift: StarGift.UniqueGift, usdCents: Int64, source: UIView?) {
        let strings = context.sharedContext.currentPresentationData.with { $0 }.strings
        let entry = GiftMiniCardEntry(gift: gift, priceTitle: strings.Gift_Stats_AveragePrice, priceCents: usdCents)
        self.present(context: context, from: from, entries: [entry], index: 0, source: source)
    }

    /// Guards against a quick double tap opening a second card.
    static weak var presented: GiftSaleMiniCardController?
    private static var isOpening = false

    private static func present(context: AccountContext, from: ViewController, entries: [GiftMiniCardEntry], index: Int, source: UIView?) {
        guard !self.isOpening, self.presented == nil, !entries.isEmpty else {
            return
        }
        self.isOpening = true
        let ids = Set(entries.compactMap { $0.gift.owner?.peerId })
        let _ = (context.engine.data.get(EngineDataMap(ids.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) }))
        |> deliverOnMainQueue).start(next: { [weak from] peers in
            GiftStatsSaleOpening.isOpening = false
            guard let from else {
                return
            }
            let resolved = entries.map { entry -> GiftMiniCardEntry in
                var entry = entry
                switch entry.gift.owner {
                case let .peerId(peerId):
                    entry.owner = peers[peerId] ?? nil
                case let .name(name):
                    entry.ownerName = name
                case let .address(address):
                    entry.ownerName = address
                case .none:
                    break
                }
                return entry
            }
            let controller = GiftSaleMiniCardController(context: context, entries: resolved, index: min(index, resolved.count - 1), source: source)
            GiftStatsSaleOpening.presented = controller
            from.present(controller, in: .window(.root))
        })
    }
}

struct GiftMiniCardEntry {
    let gift: StarGift.UniqueGift
    let priceTitle: String
    let priceCents: Int64
    var owner: EnginePeer? = nil
    /// For owners that aren't Telegram peers.
    var ownerName: String? = nil
}
