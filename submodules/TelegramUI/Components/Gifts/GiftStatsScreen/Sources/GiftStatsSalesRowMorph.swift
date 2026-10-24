import Foundation
import UIKit

/// A sales row in the card morph: the row's own views, so it looks in the morph exactly as on screen (a drawn picture
/// of the row differs slightly in the model icons and the text, and the swap at the end would show).
extension GiftStatsSalesRowView {
    /// Moves the row's views into `content` (row-sized, at the origin) for the morph and back, in the same order, on release.
    func morphMoves(into content: UIView) -> (activate: () -> Void, release: () -> Void) {
        var moved: [UIView] = []
        return (
            activate: { [weak self, weak content] in
                guard let self, let content else {
                    return
                }
                moved = self.subviews
                for view in moved {
                    content.addSubview(view)
                }
            },
            release: { [weak self] in
                guard let self else {
                    return
                }
                for view in moved {
                    self.addSubview(view)
                }
                moved = []
            }
        )
    }
}
