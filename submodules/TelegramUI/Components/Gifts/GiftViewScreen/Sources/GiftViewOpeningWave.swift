import Foundation
import UIKit

/// Plays the backdrop symbol wave once per screen, starting `lead` seconds before the sheet finishes sliding up.
final class GiftViewOpeningWave {
    /// `SheetComponent.animateIn` uses the system spring curve, which ignores the 0.4s duration it is given.
    private static let sheetDuration: Double = 0.53
    private static let lead: Double = 0.2

    private var isScheduled = false
    private var isPlayed = false

    /// Called from `viewDidAppear`, when the sheet starts sliding up.
    func schedule(in root: UIView) {
        guard !self.isScheduled else {
            return
        }
        self.isScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.0, GiftViewOpeningWave.sheetDuration - GiftViewOpeningWave.lead), execute: { [weak self, weak root] in
            if let self, let root {
                self.play(in: root)
            }
        })
    }

    /// Also called when the sheet has appeared, for presentations that skipped `schedule`.
    func play(in root: UIView) {
        guard !self.isPlayed else {
            return
        }
        self.isPlayed = true
        GiftViewOpeningWave.backdrop(in: root)?.playOpeningWave()
    }

    private static func backdrop(in view: UIView) -> GiftViewFullBackdropComponent.View? {
        if let backdrop = view as? GiftViewFullBackdropComponent.View {
            return backdrop
        }
        for subview in view.subviews {
            if let backdrop = self.backdrop(in: subview) {
                return backdrop
            }
        }
        return nil
    }
}
