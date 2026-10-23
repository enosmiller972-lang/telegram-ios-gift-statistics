import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import MultilineTextComponent
import GraphCore
import GraphUI
import GiftStats
import GiftCraftBackdrop

/// The gift card header (208 pt, centre 104) scaled about `headerMidY` and moved up to `giftCenterY`.
public enum GiftStatsHeaderMetrics {
    static let headerHeight: CGFloat = 208.0
    public static let headerMidY: CGFloat = 104.0
    public static let giftCenterY: CGFloat = 96.0
    public static let giftScale: CGFloat = 0.72
    /// Model centre in the unscaled header, as placed by `GiftCompositionComponent`.
    public static let modelRestY: CGFloat = 88.0
    public static let modelCenterY: CGFloat = giftCenterY + giftScale * (modelRestY - headerMidY)
    public static let titleCenterY: CGFloat = 162.0
    static let titleFont = Font.bold(20.0)
    static let subtitleFont = Font.regular(14.0)
    static let subtitleGap: CGFloat = 8.0
    static let subtitleToTiles: CGFloat = 20.0
}

extension GiftStatsContentComponent.View {
    func place(_ componentView: ComponentView<Empty>, size: CGSize, origin: CGPoint, transition: ComponentTransition) {
        guard let view = componentView.view else {
            return
        }
        self.place(view, frame: CGRect(origin: origin, size: size), transition: transition)
    }

    /// Sets position and bounds, not frame: views may carry a morph transform, and setting frame would misplace them.
    func place(_ view: UIView, frame: CGRect, transition: ComponentTransition) {
        if view.superview == nil {
            self.addSubview(view)
            view.frame = frame
        } else {
            transition.setPosition(view: view, position: CGPoint(x: frame.midX, y: frame.midY))
            transition.setBounds(view: view, bounds: CGRect(origin: view.bounds.origin, size: frame.size))
        }
    }

    private func layoutTitle(component: GiftStatsContentComponent, width: CGFloat, transition: ComponentTransition) -> CGFloat {
        let name = component.gift.title
        let plural = GiftStatsCollectionName.plural(name, languageCode: component.strings.baseLanguageCode)
        let font = GiftStatsHeaderMetrics.titleFont
        let size = self.title.update(
            transition: .immediate,
            component: AnyComponent(MultilineTextComponent(
                text: .plain(NSAttributedString(string: plural, font: font, textColor: .white)),
                horizontalAlignment: .center,
                maximumNumberOfLines: 1
            )),
            environment: {},
            containerSize: CGSize(width: width - component.sideInset * 2.0 - 60.0, height: 60.0)
        )
        self.titleStem = ceil((GiftStatsCollectionName.stem(of: name, plural: plural) as NSString).size(withAttributes: [.font: font]).width)
        let top = floor(GiftStatsHeaderMetrics.titleCenterY - size.height / 2.0)
        self.place(self.title, size: size, origin: CGPoint(x: floor((width - size.width) / 2.0), y: top), transition: transition)
        return top + size.height
    }

    private func layoutSubtitle(component: GiftStatsContentComponent, width: CGFloat, titleBottom: CGFloat, transition: ComponentTransition) -> CGFloat {
        let ink = GiftStatsContrast.legible(GiftStatsLook.secondaryTextColor, over: [GiftCraftBackdropColors.standard.top, GiftCraftBackdropColors.standard.bottom])
        let size = self.subtitle.update(
            transition: .immediate,
            component: AnyComponent(MultilineTextComponent(
                text: .plain(NSAttributedString(string: component.strings.Gift_Stats_CollectionInfo(component.gift.title).string, font: GiftStatsHeaderMetrics.subtitleFont, textColor: ink)),
                horizontalAlignment: .center,
                maximumNumberOfLines: 4
            )),
            environment: {},
            containerSize: CGSize(width: width - component.sideInset * 2.0 - 16.0, height: 200.0)
        )
        let top = titleBottom + GiftStatsHeaderMetrics.subtitleGap
        self.place(self.subtitle, size: size, origin: CGPoint(x: floor((width - size.width) / 2.0), y: top), transition: transition)
        return top + size.height + GiftStatsHeaderMetrics.subtitleToTiles
    }

    /// US cents; falls back to the last point of the price chart.
    func floorCents(summary: GiftStatsSummary, series: GiftStatsPriceSeries?) -> Int64? {
        return summary.floorPrice ?? series.map { Int64(saturating: $0.values.last ?? 0.0) }
    }

    private func layoutTiles(component: GiftStatsContentComponent, current: (stats: GiftStats, series: GiftStatsPriceSeries?), width: CGFloat, top: CGFloat, transition: ComponentTransition) -> CGFloat {
        let strings = component.strings
        let summary = current.stats.summary
        let count = CGFloat(self.tiles.count)
        let tileWidth = floor((width - component.sideInset * 2.0 - GiftStatsValueTileView.spacing * (count - 1.0)) / count)
        let money = GiftStatsMoney(context: component.context)
        let floorCents = self.floorCents(summary: summary, series: current.series)
        let values: [(text: String, spoken: String?, title: String, isGram: Bool, dim: String?)] = [
            (floorCents.map { money.gram(cents: $0, dateTimeFormat: component.dateTimeFormat) } ?? "-", floorCents.map { money.spokenGram(cents: $0, dateTimeFormat: component.dateTimeFormat, strings: strings) }, strings.Gift_Stats_Floor, floorCents != nil, floorCents.map { money.usd(cents: $0, dateTimeFormat: component.dateTimeFormat) }),
            (presentationStringsFormattedNumber(summary.supply, component.dateTimeFormat.groupingSeparator), nil, strings.Gift_Stats_TileSupply, false, nil),
            (presentationStringsFormattedNumber(summary.listedCount, component.dateTimeFormat.groupingSeparator), nil, strings.Gift_Stats_TileListed, false, nil)
        ]
        for (index, tile) in self.tiles.enumerated() {
            let frame = CGRect(x: component.sideInset + CGFloat(index) * (tileWidth + GiftStatsValueTileView.spacing), y: top, width: tileWidth, height: GiftStatsValueTileView.height)
            self.place(tile, frame: frame, transition: transition)
            tile.update(text: values[index].text, spoken: values[index].spoken, title: values[index].title, isGram: values[index].isGram, dim: values[index].dim, tile: GiftStatsTileStyle.surface(palette: component.palette), size: frame.size, strings: strings, transition: transition)
        }
        return top + GiftStatsValueTileView.height + GiftStatsSpacing.panelToSection
    }

    func layoutContent(component: GiftStatsContentComponent, current: (stats: GiftStats, series: GiftStatsPriceSeries?), availableSize: CGSize, transition: ComponentTransition) -> CGSize {
        let width = availableSize.width
        let fraction = self.fraction ?? (0.0 ... 1.0)

        let titleBottom = self.layoutTitle(component: component, width: width, transition: transition)
        let tilesTop = self.layoutSubtitle(component: component, width: width, titleBottom: titleBottom, transition: transition)
        var originY = self.layoutTiles(component: component, current: current, width: width, top: tilesTop, transition: transition)
        originY = self.layoutItem(component: component, originY: originY, width: width, transition: transition)
        return self.layoutBody(component: component, current: current, fraction: fraction, originY: originY, width: width, transition: transition)
    }
}
