import UIKit
import Display
import GraphCore

enum GiftChartRangeStyle {
    private static var cache: UIImage?

    /// Stretchable 114x42 frame with 11pt caps.
    static func cropImage() -> UIImage? {
        if let cache = self.cache {
            return cache
        }
        let image = generateImage(CGSize(width: 114.0, height: 42.0), rotatedContext: { size, context in
            context.clear(CGRect(origin: .zero, size: size))
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor(white: 1.0, alpha: 0.42).cgColor, UIColor(white: 1.0, alpha: 0.18).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0.0, 1.0])

            let left = UIBezierPath(roundedRect: CGRect(x: 0.0, y: 0.0, width: 11.0, height: 42.0), byRoundingCorners: [.topLeft, .bottomLeft], cornerRadii: CGSize(width: 7.0, height: 7.0))
            let right = UIBezierPath(roundedRect: CGRect(x: 103.0, y: 0.0, width: 11.0, height: 42.0), byRoundingCorners: [.topRight, .bottomRight], cornerRadii: CGSize(width: 7.0, height: 7.0))
            for path in [left, right] {
                context.saveGState()
                context.addPath(path.cgPath)
                context.clip()
                if let gradient {
                    context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: 42.0), options: [])
                }
                context.restoreGState()
            }
            context.setLineWidth(0.75)
            context.setStrokeColor(UIColor(white: 1.0, alpha: 0.6).cgColor)
            for rect in [CGRect(x: 0.375, y: 0.375, width: 10.6, height: 41.25), CGRect(x: 103.0, y: 0.375, width: 10.6, height: 41.25)] {
                let corners: UIRectCorner = rect.minX < 50.0 ? [.topLeft, .bottomLeft] : [.topRight, .bottomRight]
                context.addPath(UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: 6.6, height: 6.6)).cgPath)
                context.strokePath()
            }
            context.setFillColor(UIColor(white: 1.0, alpha: 0.4).cgColor)
            context.fill(CGRect(x: 11.0, y: 0.0, width: 92.0, height: 0.75))
            context.fill(CGRect(x: 11.0, y: 41.25, width: 92.0, height: 0.75))

            context.setLineCap(.round)
            context.setLineWidth(1.5)
            context.setStrokeColor(UIColor(white: 1.0, alpha: 0.95).cgColor)
            context.move(to: CGPoint(x: 7.0, y: 17.0))
            context.addLine(to: CGPoint(x: 4.0, y: 21.0))
            context.addLine(to: CGPoint(x: 7.0, y: 25.0))
            context.strokePath()
            context.move(to: CGPoint(x: 107.0, y: 17.0))
            context.addLine(to: CGPoint(x: 110.0, y: 21.0))
            context.addLine(to: CGPoint(x: 107.0, y: 25.0))
            context.strokePath()
        })?.resizableImage(withCapInsets: UIEdgeInsets(top: 15.0, left: 11.0, bottom: 15.0, right: 11.0), resizingMode: .stretch)
        self.cache = image
        return image
    }

    static let minimumWindowWidth: CGFloat = 64.0
    static let minimumTouchWidth: CGFloat = 44.0
    /// How far a handle's touch target reaches into the window; the rest lies outside.
    private static let handleInnerReach: CGFloat = 10.0

    /// A narrow window is treated as `minimumWindowWidth` around its center so the three targets never overlap.
    static func hitZones(lowerX: CGFloat, upperX: CGFloat) -> (lower: ClosedRange<CGFloat>, center: ClosedRange<CGFloat>, upper: ClosedRange<CGFloat>) {
        let center = (lowerX + upperX) / 2.0
        let half = max(upperX - lowerX, self.minimumWindowWidth) / 2.0
        let left = center - half
        let right = center + half
        let outer = self.minimumTouchWidth - self.handleInnerReach
        return (
            lower: (left - outer) ... (left + self.handleInnerReach),
            center: (left + self.handleInnerReach) ... (right - self.handleInnerReach),
            upper: (right - self.handleInnerReach) ... (right + outer)
        )
    }
}
