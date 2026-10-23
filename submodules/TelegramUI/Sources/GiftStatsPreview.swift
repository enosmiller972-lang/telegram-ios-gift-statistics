import Foundation
import AccountContext
import TelegramCore
import SwiftSignalKit
import GiftStats
import GiftStatsPreview
import TelegramUIPreferences

/// Stand-in gift stats provider switched by "Gift Stats Preview Data" in debug settings.
enum GiftStatsPreviewInstaller {
    private static let disposable = MetaDisposable()

    /// Installs the preview provider when enabled in experimental settings.
    static func install(context: AccountContext) {
        self.disposable.set((context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.experimentalUISettings])
        |> map { sharedData -> Bool in
            let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings]?.get(ExperimentalUISettings.self) ?? ExperimentalUISettings.defaultSettings
            return settings.giftStatsPreview
        }
        |> distinctUntilChanged
        |> deliverOnMainQueue).startStrict(next: { [weak context] isEnabled in
            guard let context else {
                return
            }
            if isEnabled {
                GiftStatsService.shared.provider = self.makeProvider(context: context)
            } else if GiftStatsService.shared.provider is LocalGiftStatsProvider {
                GiftStatsService.shared.provider = UnavailableGiftStatsProvider()
            }
        }))
    }

    private static func makeProvider(context: AccountContext) -> GiftStatsProvider {
        let sources = LocalGiftStatsProvider.Sources(
            market: { [weak context] giftId in
                guard let context else {
                    return .complete()
                }
                return market(context: context, giftId: giftId)
            },
            models: { [weak context] giftId in
                guard let context else {
                    return .single(GiftStatsVariants(models: [], backdrops: []))
                }
                return models(context: context, giftId: giftId)
            }
        )
        return LocalGiftStatsProvider(sources: sources)
    }

    /// Resolves the collection floor and withdrawal conversion rate.
    private static func market(context: AccountContext, giftId: Int64) -> Signal<GiftStatsMarket, NoError> {
        let configuration = StarsSubscriptionConfiguration.with(appConfiguration: context.currentAppConfiguration.with { $0 })
        // Thousandths of a US dollar per 100 stars.
        let centsPerStar = Double(configuration.usdWithdrawRate) / 1000.0
        return context.engine.payments.cachedStarGifts()
        |> filter { $0 != nil }
        |> take(1)
        |> timeout(3.0, queue: Queue.mainQueue(), alternate: .single(nil))
        |> map { gifts -> GiftStatsMarket in
            var floorStars: Int64?
            for gift in gifts ?? [] {
                if case let .generic(generic) = gift, generic.id == giftId {
                    if let minResaleStars = generic.availability?.minResaleStars, minResaleStars > 0 {
                        floorStars = minResaleStars
                    }
                    break
                }
            }
            return GiftStatsMarket(collectionFloorStars: floorStars, usdCentsPerStar: centsPerStar)
        }
    }

    private static let ownerNames = ["durov", "telegram", "TelegramTips", "tginfo", "designers", "fragment", "wallet", "toncoin", "contest", "PremiumBot"]
    private static var resolvedOwners: [EnginePeer.Id]?

    private static func owners(context: AccountContext) -> Signal<[EnginePeer.Id], NoError> {
        if let resolvedOwners {
            return .single(resolvedOwners)
        }
        let resolves = ownerNames.map { name -> Signal<EnginePeer.Id?, NoError> in
            return context.engine.peers.resolvePeerByName(name: name, referrer: nil)
            |> mapToSignal { result -> Signal<EnginePeer.Id?, NoError> in
                guard case let .result(peer) = result else {
                    return .complete()
                }
                return .single(peer?.id)
            }
            |> take(1)
            |> timeout(4.0, queue: Queue.mainQueue(), alternate: .single(nil))
        }
        return combineLatest(resolves)
        |> map { ids -> [EnginePeer.Id] in
            let found = ids.compactMap { $0 }
            if !found.isEmpty {
                resolvedOwners = found
            }
            return found
        }
    }

    /// Fetches upgrade variant models and backdrops.
    private static func models(context: AccountContext, giftId: Int64) -> Signal<GiftStatsVariants, NoError> {
        return combineLatest(context.engine.payments.getStarGiftUpgradeAttributes(giftId: giftId), owners(context: context))
        |> map { attributes, owners -> GiftStatsVariants in
            var models: [GiftStatsModelInfo] = []
            var backdrops: [GiftStatsBackdropInfo] = []
            var symbols: [StarGift.UniqueGift.Attribute] = []
            for attribute in attributes ?? [] {
                if case let .model(name, file, rarity, _) = attribute {
                    models.append(GiftStatsModelInfo(name: name, file: file, rarity: rarity))
                } else if case let .backdrop(_, _, innerColor, outerColor, _, _, rarity) = attribute {
                    backdrops.append(GiftStatsBackdropInfo(backdrop: GiftSaleBackdrop(innerColor: innerColor, outerColor: outerColor), rarity: rarity, attribute: attribute))
                } else if case .pattern = attribute {
                    symbols.append(attribute)
                }
            }
            return GiftStatsVariants(models: models, backdrops: backdrops, symbols: symbols, owners: owners)
        }
    }
}
