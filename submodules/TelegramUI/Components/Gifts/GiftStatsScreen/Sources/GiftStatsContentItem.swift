import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramPresentationData
import AccountContext
import MultilineTextComponent

extension GiftStatsContentComponent.View {
    /// The user's own gift with its sell button. Returns where the next section starts (`originY` when the gift is not theirs).
    func layoutItem(component: GiftStatsContentComponent, originY: CGFloat, width: CGFloat, transition: ComponentTransition) -> CGFloat {
        guard let item = component.item else {
            self.itemHeader.view?.removeFromSuperview()
            self.itemPanel.removeFromSuperview()
            self.itemRow.removeFromSuperview()
            return originY
        }
        let palette = component.palette
        let sideInset = component.sideInset
        let contentWidth = width - sideInset * 2.0
        var originY = originY
        let headerSize = self.itemHeader.update(
            transition: .immediate,
            component: AnyComponent(MultilineTextComponent(text: .plain(NSAttributedString(string: component.strings.Gift_Stats_YourItem.uppercased(), font: Font.regular(13.0), textColor: palette.label)))),
            environment: {},
            containerSize: CGSize(width: contentWidth - 32.0, height: 30.0)
        )
        self.place(self.itemHeader, size: headerSize, origin: CGPoint(x: sideInset + 16.0, y: originY), transition: transition)
        originY += headerSize.height + GiftStatsSpacing.headerToPanel

        let theme = component.context.sharedContext.currentPresentationData.with { $0 }.theme
        let rowSize = self.itemRow.update(
            gift: component.gift,
            item: item,
            context: component.context,
            money: GiftStatsMoney(context: component.context),
            strings: component.strings,
            dateTimeFormat: component.dateTimeFormat,
            palette: palette,
            buttonFill: theme.list.itemCheckColors.fillColor,
            buttonForeground: theme.list.itemCheckColors.foregroundColor,
            width: contentWidth,
            isRTL: GiftStatsEnvironment.isRTL(strings: component.strings),
            action: component.sell,
            open: component.openItem
        )
        let frame = CGRect(origin: CGPoint(x: sideInset, y: originY), size: rowSize)
        self.place(self.itemPanel, frame: frame, transition: transition)
        self.itemPanel.update(color: palette.panel)
        self.place(self.itemRow, frame: frame, transition: transition)
        return originY + rowSize.height + GiftStatsSpacing.panelToSection
    }
}
