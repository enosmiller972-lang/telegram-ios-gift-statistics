import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import ComponentFlow
import TableComponent
import GiftStats
import GiftStatsScreen

extension GiftViewSheetContent.State {
    /// Loads model and collection stats for the "Value" row. Without a provider the stock row is kept.
    func startGiftStatsUpdates() {
        guard let arguments = self.subject.arguments, case let .unique(gift) = arguments.gift, let modelScope = gift.modelStatsScope else {
            return
        }
        let provider = GiftStatsService.shared.provider
        guard provider.isAvailable else {
            return
        }
        GiftStatsEmbedded.prepare()
        self.giftStatsDisposable?.dispose()
        self.giftCollectionStatsDisposable?.dispose()
        self.giftValueInfoDisposable?.dispose()
        // Same request as the stock value screen; the row and the own gift in stats show this price.
        if gift.valueAmount != nil {
            self.giftValueInfoDisposable = (self.context.engine.payments.getUniqueStarGiftValueInfo(slug: gift.slug)
            |> deliverOnMainQueue).startStrict(next: { [weak self] info in
                guard let self else {
                    return
                }
                self.giftValueInfo = info
                self.isGiftValueInfoResolved = true
                self.updated(transition: .immediate)
            })
        } else {
            self.isGiftValueInfoResolved = true
        }
        self.giftStatsDisposable = (provider.stats(for: gift, scope: modelScope)
        |> deliverOnMainQueue).startStrict(next: { [weak self] stats in
            guard let self else {
                return
            }
            self.giftStats = stats
            self.updated(transition: .immediate)
        })
        // The row opens stats only once collection stats are loaded, so they show instantly.
        self.giftCollectionStatsDisposable = (provider.stats(for: gift, scope: .collection)
        |> deliverOnMainQueue).startStrict(next: { [weak self] stats in
            guard let self else {
                return
            }
            self.giftCollectionStats = stats
            self.updated(transition: .immediate)
        })
    }

    /// Morphs the card into the stats in place. No-op until collection stats are loaded.
    func openGiftStats() {
        guard let controller = self.getController() as? GiftViewScreen, let arguments = self.subject.arguments, case let .unique(gift) = arguments.gift, let collectionStats = self.giftCollectionStats else {
            return
        }
        let rowView = controller.node.hostView.findTaggedView(tag: self.giftStatsRowTag)
        // Owned or hosted for the user, i.e. when the stock card offers "Sell".
        let accountPeerId = self.context.account.peerId
        var isMine = gift.hostPeerId == accountPeerId
        if case let .peerId(peerId) = gift.owner, peerId == accountPeerId {
            isMine = true
        }
        var item: GiftStatsYourItem?
        if isMine, let cents = giftStatsValueCents(state: self, uniqueGift: gift) {
            item = GiftStatsYourItem(usdCents: cents, isListed: !(gift.resellAmounts ?? []).isEmpty)
        }
        self.statsEntry?(GiftViewStatsRequest(
            context: self.context,
            gift: gift,
            collectionStats: collectionStats,
            item: item,
            valueRow: rowView,
            openStore: { [weak self] from in
                guard let self, let generic = self.starGiftsMap[gift.giftId] else {
                    return
                }
                let store = self.context.sharedContext.makeGiftStoreController(context: self.context, peerId: self.context.account.peerId, gift: generic)
                from.push(store)
            },
            sell: { [weak self] in
                self?.resellGift()
            },
            openSale: { [weak self] from, sales, index, source in
                guard let self else {
                    return
                }
                GiftStatsSaleOpening.open(context: self.context, from: from, sales: sales, index: index, source: source)
            },
            openItem: { [weak self] from, source in
                guard let self, let item else {
                    return
                }
                GiftStatsSaleOpening.openOwn(context: self.context, from: from, gift: gift, usdCents: item.usdCents, source: source)
            }
        ))
    }
}

/// US cents: Telegram's value info if the gift has one, else the model floor (never `valueAmount`, which includes auctions).
/// Nil while the needed data is loading.
func giftStatsValueCents(state: GiftViewSheetContent.State, uniqueGift: StarGift.UniqueGift) -> Int64? {
    guard let stats = state.giftStats, state.isGiftValueInfoResolved, let series = GiftStatsPriceSeries(graph: stats.priceGraph) else {
        return nil
    }
    return GiftStatsValueHeader.make(gift: uniqueGift, info: state.giftValueInfo)?.usdCents ?? stats.summary.floorPrice ?? Int64(saturating: series.values.last ?? 0.0)
}

/// Nil until model and collection stats are loaded; the stock row is used then.
func giftStatsValueRow(state: GiftViewSheetContent.State, uniqueGift: StarGift.UniqueGift, theme: PresentationTheme, strings: PresentationStrings) -> TableComponent.Item? {
    guard state.giftCollectionStats != nil, let floorCents = giftStatsValueCents(state: state, uniqueGift: uniqueGift) else {
        return nil
    }
    let dateTimeFormat = state.context.sharedContext.currentPresentationData.with { $0 }.dateTimeFormat
    let money = GiftStatsMoney(context: state.context)
    return TableComponent.Item(
        // Distinct from the stock "fiatValue" id: reusing an id with a different child type crashes the table update.
        id: "fiatValueStats",
        title: strings.Gift_Unique_Value,
        component: AnyComponent(GiftStatsRowValueComponent(theme: theme, gramText: money.gram(cents: floorCents, dateTimeFormat: dateTimeFormat), usdText: money.usd(cents: floorCents, dateTimeFormat: dateTimeFormat), viewMoreText: strings.Gift_Stats_ViewMore, dimColor: GiftViewFullBackdrop.colors(of: uniqueGift) != nil ? GiftTonalPalette.cached(gift: uniqueGift).dim : nil)),
        insets: UIEdgeInsets(top: 0.0, left: 10.0, bottom: 0.0, right: 12.0),
        action: { [weak state] in
            state?.openGiftStats()
        },
        actionTag: state.giftStatsRowTag,
        accessibilityLabel: GiftStatsFormat.join([strings.Gift_Unique_Value, money.spokenGram(cents: floorCents, dateTimeFormat: dateTimeFormat, strings: strings), strings.Gift_Stats_ViewMore], strings: strings)
    )
}
