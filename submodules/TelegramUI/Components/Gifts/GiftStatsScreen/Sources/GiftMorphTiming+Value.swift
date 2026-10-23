import Foundation
import UIKit

// The "Your Item" panel.
extension GiftMorphTiming {
    public static let valueHeading = GiftMorphWindow(start: 0.55, length: 0.40)
    public static let valueHeadingRise: CGFloat = 6.0
    public static let valueRow = GiftMorphWindow(start: 0.45, length: 0.45)
    // Minimum visible share for the panel to morph back into the table; otherwise it fades in place.
    public static let valueSourceShare: CGFloat = 0.5
}
