import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramCore
import TelegramPresentationData
import MultilineTextComponent
import GraphCore
import GraphUI
import GiftStats

extension GiftStatsContentComponent.View {
    /// Lays out the sales log and the charts from `originY` down; returns the size of the whole content.
    func layoutBody(component: GiftStatsContentComponent, current: (stats: GiftStats, series: GiftStatsPriceSeries?), fraction: ClosedRange<CGFloat>, originY: CGFloat, width: CGFloat, transition: ComponentTransition) -> CGSize {
        let strings = component.strings
        let dateTimeFormat = component.dateTimeFormat
        let sideInset = component.sideInset
        let contentWidth = width - sideInset * 2.0
        let stats = current.stats
        let money = GiftStatsMoney(context: component.context)
        let palette = component.palette
        var originY = originY
        // Rounded to the minute so relative times in the log only change once a minute.
        let now = Int32(Date().timeIntervalSince1970) / 60 * 60

        let pages = self.salesPages(for: stats)
        if !pages.items.isEmpty {
            let headerSize = self.salesLogHeader.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(text: .plain(NSAttributedString(string: strings.Gift_Stats_RecentSales.uppercased(), font: Font.regular(13.0), textColor: palette.label)))),
                environment: {},
                containerSize: CGSize(width: contentWidth - 32.0, height: 30.0)
            )
            self.place(self.salesLogHeader, size: headerSize, origin: CGPoint(x: sideInset + 16.0, y: originY), transition: transition)
            originY += headerSize.height + GiftStatsSpacing.headerToPanel
            let logSize = self.salesLog.update(
                transition: transition,
                component: AnyComponent(GiftStatsRecentSalesComponent(
                    context: component.context,
                    money: money,
                    strings: strings,
                    dateTimeFormat: dateTimeFormat,
                    palette: palette,
                    now: now,
                    sales: pages.items,
                    hasMore: !pages.isEnd,
                    isLoadingMore: pages.isLoading,
                    isExpanded: self.salesLogIsExpanded,
                    openHeight: self.salesLogOpenHeight,
                    cardShortfall: { [weak self] in
                        return self?.salesLogShortfall() ?? 0.0
                    },
                    openSale: { [weak self] index, source in
                        guard let self, let component = self.component, let pages = self.salesPages else {
                            return
                        }
                        component.openSale(pages.items, index, source)
                    },
                    toggle: { [weak self] in
                        self?.toggleSalesLog()
                    },
                    loadMore: { [weak self] in
                        self?.loadMoreSales()
                    }
                )),
                environment: {},
                containerSize: CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
            )
            let logFrame = CGRect(origin: CGPoint(x: sideInset, y: originY), size: logSize)
            self.place(self.salesLogPanel, frame: logFrame, transition: transition)
            self.salesLogPanel.update(color: palette.panel)
            self.place(self.salesLog, size: logSize, origin: logFrame.origin, transition: transition)
            originY += logSize.height + GiftStatsSpacing.panelToSection
        }

        // Chart values are US cents, shown in Gram.
        let gramAxis = ChartValueFormat(divisor: money.chartDivisor, prefix: "", groupingSeparator: dateTimeFormat.groupingSeparator, decimalSeparator: dateTimeFormat.decimalSeparator)
        let priceText: (Double) -> NSAttributedString = { cents in
            let text = NSMutableAttributedString()
            text.append(GiftStatsGram.attachment(fontSize: GiftStatsScrubOverlay.valueFont.pointSize, color: GiftStatsScrubOverlay.valueColor))
            text.append(NSAttributedString(string: " " + money.gram(cents: Int64(saturating: cents.rounded()), dateTimeFormat: dateTimeFormat), attributes: [.font: GiftStatsScrubOverlay.valueFont, .foregroundColor: GiftStatsScrubOverlay.valueColor]))
            text.append(NSAttributedString(string: "  " + money.usd(cents: Int64(saturating: cents.rounded()), dateTimeFormat: dateTimeFormat), attributes: [.font: Font.regular(12.0), .foregroundColor: GiftStatsContrast.legible(GiftStatsLook.secondaryTextColor, over: [palette.button.fill])]))
            return text
        }
        let priceSpoken: (Double) -> String = { cents in
            return money.spokenGram(cents: Int64(saturating: cents.rounded()), dateTimeFormat: dateTimeFormat, strings: strings)
        }
        if let series = current.series {
            originY = self.placeChart(
                header: self.priceHeader, headerText: strings.Gift_Stats_PriceTitle, panel: self.pricePanel, chart: self.priceChart,
                chartComponent: GiftStatsChartComponent(
                    strings: strings, graph: stats.priceGraph, type: .lines, valueFormat: gramAxis, dateTimeFormat: dateTimeFormat,
                    range: GiftStatsChartRange(fraction: fraction, token: self.priceToken),
                    series: series,
                    palette: palette,
                    title: strings.Gift_Stats_PriceTitle,
                    spokenValue: priceSpoken,
                    formatValue: priceText,
                    userDidChangeRange: { [weak self] range in
                        if let self {
                            self.rangeChanged(by: self.priceChart, fraction: range)
                        }
                    },
                    labelsGate: component.labelsGate
                ),
                palette: palette, originY: originY, sideInset: sideInset, contentWidth: contentWidth, transition: transition
            )
        } else {
            self.removeSection(header: self.priceHeader, panel: self.pricePanel, chart: self.priceChart)
        }
        if let series = self.salesSeries {
            originY = self.placeChart(
                header: self.salesHeader, headerText: strings.Gift_Stats_SalesTitle, panel: self.salesPanel, chart: self.salesChart,
                chartComponent: GiftStatsChartComponent(
                    strings: strings, graph: stats.salesGraph, type: .bars, valueFormat: nil, dateTimeFormat: dateTimeFormat,
                    range: GiftStatsChartRange(fraction: fraction, token: self.salesToken),
                    series: series,
                    palette: palette,
                    title: strings.Gift_Stats_SalesTitle,
                    spokenValue: { presentationStringsFormattedNumber(Int64(saturating: $0.rounded()), dateTimeFormat.groupingSeparator) },
                    formatValue: { NSAttributedString(string: presentationStringsFormattedNumber(Int64(saturating: $0.rounded()), dateTimeFormat.groupingSeparator), attributes: [.font: GiftStatsScrubOverlay.valueFont, .foregroundColor: GiftStatsScrubOverlay.valueColor]) },
                    userDidChangeRange: { [weak self] range in
                        if let self {
                            self.rangeChanged(by: self.salesChart, fraction: range)
                        }
                    },
                    labelsGate: component.labelsGate
                ),
                palette: palette, originY: originY, sideInset: sideInset, contentWidth: contentWidth, transition: transition
            )
        } else {
            self.removeSection(header: self.salesHeader, panel: self.salesPanel, chart: self.salesChart)
        }

        component.buyChanged(stats.summary.listedCount, self.floorCents(summary: stats.summary, series: current.series))
        return CGSize(width: width, height: originY)
    }

    private func removeSection(header: ComponentView<Empty>, panel: GiftTonalPanelView, chart: ComponentView<Empty>) {
        header.view?.removeFromSuperview()
        panel.removeFromSuperview()
        chart.view?.removeFromSuperview()
    }

    private func placeChart(
        header: ComponentView<Empty>, headerText: String, panel: GiftTonalPanelView, chart: ComponentView<Empty>, chartComponent: GiftStatsChartComponent,
        palette: GiftTonalPalette, originY: CGFloat, sideInset: CGFloat, contentWidth: CGFloat, transition: ComponentTransition
    ) -> CGFloat {
        var originY = originY
        let headerSize = header.update(
            transition: .immediate,
            component: AnyComponent(MultilineTextComponent(text: .plain(NSAttributedString(string: headerText.uppercased(), font: Font.regular(13.0), textColor: palette.label)))),
            environment: {},
            containerSize: CGSize(width: contentWidth - 32.0, height: 30.0)
        )
        self.place(header, size: headerSize, origin: CGPoint(x: sideInset + 16.0, y: originY), transition: transition)
        originY += headerSize.height + GiftStatsSpacing.headerToPanel

        let chartSize = chart.update(transition: transition, component: AnyComponent(chartComponent), environment: {}, containerSize: CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        let frame = CGRect(origin: CGPoint(x: sideInset, y: originY), size: chartSize)
        self.place(panel, frame: frame, transition: transition)
        panel.update(color: palette.panel)
        self.place(chart, size: chartSize, origin: frame.origin, transition: transition)
        if let view = chart.view {
            view.layer.cornerRadius = GiftTonalPalette.cornerRadius
            view.layer.cornerCurve = .continuous
        }
        return originY + chartSize.height + GiftStatsSpacing.panelToSection
    }
}
