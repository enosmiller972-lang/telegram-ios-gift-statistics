import Foundation
#if os(macOS)
import Cocoa
#else
import UIKit
#endif

private enum GiftChartBars {
    /// Fraction of a slot left empty between bars.
    static let gap: CGFloat = 0.34
    static let topAlpha: CGFloat = 0.9
    static let bottomAlpha: CGFloat = 0.25
    static let dimmedAlpha: CGFloat = 0.35
}

/// Gift statistics bars, used only when `giftRole` is set.
extension BarChartRenderer {
    /// The range slider preview has narrower bars, so it allows more of them.
    func giftLevel(forVisibleRange range: ClosedRange<CGFloat>) -> GiftChartBarLevels.Level {
        return self.giftLevels.level(forVisibleRange: range, maxVisible: self.giftRole == .preview ? 72 : GiftChartBarLevels.maxVisible)
    }

    /// Sum of the visible components.
    func giftTotal(of data: BarsData, at index: Int) -> CGFloat {
        var total: CGFloat = 0.0
        for (componentIndex, component) in data.components.enumerated() where componentIndex < self.componentsAnimators.count {
            total += component.values[index] * self.componentsAnimators[componentIndex].current
        }
        return total
    }

    func giftVisiblePeak(range: ClosedRange<CGFloat>) -> CGFloat {
        let data = self.giftLevel(forVisibleRange: range).data
        var peak: CGFloat = 0.0
        for index in data.locations.indices where data.locations[index] >= range.lowerBound && data.locations[index] - data.barWidth <= range.upperBound {
            peak = max(peak, self.giftTotal(of: data, at: index))
        }
        return peak
    }

    func renderGiftBars(context: CGContext, bounds: CGRect, chartFrame: CGRect, alpha chartsAlpha: CGFloat) {
        guard !self.bars.locations.isEmpty else {
            return
        }
        let level = self.giftLevel(forVisibleRange: self.horizontalRange.end)
        let data = level.data
        let range = renderRange(bounds: bounds, chartFrame: chartFrame)
        guard var index = data.locations.firstIndex(where: { $0 >= range.lowerBound }) else {
            return
        }
        index = max(0, index - 1)
        let isPreview = self.giftRole == .preview
        let selection = self.selectedIndexAnimator.current
        var selectedBucket: Int?
        if !isPreview, let raw = self.selectedBarIndex, raw < level.rawToBucket.count {
            selectedBucket = level.rawToBucket[raw]
        }
        let baseY = transform(toChartCoordinateVertical: 0.0, chartFrame: chartFrame)
        let space = CGColorSpaceCreateDeviceRGB()
        // Clip horizontally to the plot like the line; the selected bar's glow may extend vertically.
        context.saveGState()
        context.clip(to: CGRect(x: chartFrame.minX, y: bounds.minY, width: chartFrame.width, height: bounds.height))
        defer {
            context.restoreGState()
        }

        while index < data.locations.count {
            let location = data.locations[index]
            let total = self.giftTotal(of: data, at: index)
            let growth = isPreview ? 1.0 : self.giftBarGrowth(total: total)
            let topY = transform(toChartCoordinateVertical: total * growth, chartFrame: chartFrame)
            let slotRight = transform(toChartCoordinateHorizontal: location, chartFrame: chartFrame)
            let slotLeft = transform(toChartCoordinateHorizontal: location - data.barWidth, chartFrame: chartFrame)
            let width = max(1.0, (slotRight - slotLeft) * (1.0 - GiftChartBars.gap))
            let x = (slotLeft + slotRight) / 2.0 - width / 2.0
            let height = baseY - topY
            if height >= 0.5 && total > 0.0 {
                let radius = min(width / 2.0, height)
                let path = CGMutablePath()
                path.move(to: CGPoint(x: x, y: baseY))
                path.addLine(to: CGPoint(x: x, y: topY + radius))
                path.addArc(tangent1End: CGPoint(x: x, y: topY), tangent2End: CGPoint(x: x + radius, y: topY), radius: radius)
                path.addArc(tangent1End: CGPoint(x: x + width, y: topY), tangent2End: CGPoint(x: x + width, y: topY + radius), radius: radius)
                path.addLine(to: CGPoint(x: x + width, y: baseY))
                path.closeSubpath()

                let isSelected = selectedBucket == index
                // Fade bars cut by the plot edge so no sliver remains.
                let shown = max(0.0, min(x + width, chartFrame.maxX) - max(x, chartFrame.minX)) / width
                let edge = min(1.0, max(0.0, (shown - 0.25) / 0.6))
                let factor: CGFloat = (isSelected ? 1.0 : 1.0 - (1.0 - GiftChartBars.dimmedAlpha) * (selectedBucket == nil ? 0.0 : selection)) * edge
                if isSelected && selection > 0.01 {
                    context.saveGState()
                    context.setShadow(offset: .zero, blur: 12.0, color: UIColor(white: 1.0, alpha: 0.6 * selection * chartsAlpha).cgColor)
                    context.setFillColor(UIColor(white: 1.0, alpha: selection * chartsAlpha).cgColor)
                    context.addPath(path)
                    context.fillPath()
                    context.restoreGState()
                }
                let top = GiftChartBars.topAlpha * factor * chartsAlpha
                let bottom = GiftChartBars.bottomAlpha * factor * chartsAlpha
                let colors = [UIColor(white: 1.0, alpha: top).cgColor, UIColor(white: 1.0, alpha: bottom).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0.0, 1.0]) {
                    context.saveGState()
                    context.addPath(path)
                    context.clip()
                    context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: topY), end: CGPoint(x: 0.0, y: baseY), options: [])
                    context.restoreGState()
                }
            }
            if location > range.upperBound {
                break
            }
            index += 1
        }
    }
}
