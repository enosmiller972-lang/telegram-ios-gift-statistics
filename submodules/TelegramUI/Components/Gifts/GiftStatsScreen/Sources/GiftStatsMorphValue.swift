import Foundation
import UIKit
import Display
import ComponentFlow

/// The user's own gift panel as a morph end: it grows out of the card's table; its heading fades on its own.
public struct GiftStatsMorphValue {
    public var panel: GiftMorphEnd
    /// Faded independently.
    public var lines: [UIView]
    /// The panel is a piece only above `GiftMorphTiming.valueSourceShare`.
    public var share: CGFloat

    public var views: [UIView] {
        return self.panel.reveal + self.lines
    }
}

extension GiftStatsContentComponent.View {
    func morphValue(in card: UIView, plan: GiftStatsBackPlan?) -> GiftStatsMorphValue? {
        let panel = self.itemPanel
        let row = self.itemRow
        guard panel.superview != nil, row.superview != nil, panel.bounds.width > 0.0 else {
            return nil
        }
        let reveal: [UIView] = [panel, row]
        let end = GiftMorphEnd(
            reveal: reveal,
            look: { [weak panel, weak card] in
                guard let panel, let card else {
                    return GiftMorphLook(frame: .zero, radius: 0.0, flat: .control)
                }
                return panel.morphLook(in: card)
            },
            things: { [weak row, weak card] isFrozen in
                guard let row, let card, let picture = GiftMorphCapture.picture(of: row) else {
                    return []
                }
                return [GiftMorphCapture.thing(picture, standingFor: row, in: card, isFrozen: isFrozen)]
            },
            hide: {
                for view in reveal {
                    view.alpha = 0.0
                }
            }
        )
        let lines = [self.itemHeader.view].compactMap { $0 }.filter { $0.superview != nil }
        return GiftStatsMorphValue(panel: end, lines: lines, share: plan?.valueShare ?? 1.0)
    }
}
