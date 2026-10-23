import Foundation
#if os(macOS)
import Cocoa
#else
import UIKit
#endif

/// Curves stroked in the last frame (after downsampling and morph), so dots read from them stay on the line during animations.
struct GiftChartLineState {
    var fits: [GiftChartCurve.Fit] = []
    /// Drawn fraction of the plot width during the draw-in; nil when complete.
    var reveal: CGFloat?

    mutating func set(_ fit: GiftChartCurve.Fit, lineIndex: Int) {
        while self.fits.count <= lineIndex {
            self.fits.append(GiftChartCurve.Fit([]))
        }
        self.fits[lineIndex] = fit
    }
}

extension LinesChartRenderer {
    func drawGiftLine(context: CGContext, chartPoints: [CGPoint], lineIndex: Int, color: GColor, chartFrame: CGRect) {
        let points = GiftChartCurve.downsample(chartPoints, bucketWidth: LinesChartRenderer.giftPointSpacing)
        guard points.count >= 2 else {
            return
        }
        let fit = GiftChartCurve.Fit(points)
        let path = fit.path
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if self.giftRole == .preview {
            context.setLineWidth(lineIndex == 0 ? 1.2 : 0.9)
            context.setStrokeColor(color.withAlphaComponent(lineIndex == 0 ? 0.85 : 0.45).cgColor)
            context.addPath(path)
            context.strokePath()
            return
        }
        self.giftState.set(fit, lineIndex: lineIndex)
        context.saveGState()
        if let reveal = self.giftState.reveal {
            // Cut at the head where `drawGiftDot` puts the dot; in the last 3% the cut widens by the glow so the final frame matches the static one.
            let edge = self.giftRevealEdge(reveal: reveal, fit: fit, chartFrame: chartFrame)
            let glowMargin: CGFloat = 14.0 * min(1.0, max(0.0, (reveal - 0.97) / 0.03))
            context.clip(to: CGRect(x: -10000.0, y: -10000.0, width: edge + glowMargin + 10000.0, height: 20000.0))
        }
        if lineIndex == 0 {
            self.drawGiftArea(context: context, path: path, points: points, chartFrame: chartFrame)
            context.saveGState()
            context.setShadow(offset: .zero, blur: 7.0, color: UIColor(white: 1.0, alpha: 0.4).cgColor)
            context.setLineWidth(2.0)
            context.setStrokeColor(UIColor.white.cgColor)
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        } else {
            context.saveGState()
            context.setLineWidth(1.25)
            context.setStrokeColor(UIColor(white: 1.0, alpha: 0.45).cgColor)
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        }
        context.restoreGState()
    }

    /// Spans the curve or the plot, whichever is wider, so nothing is left to appear at the end.
    func giftRevealEdge(reveal: CGFloat, fit: GiftChartCurve.Fit, chartFrame: CGRect) -> CGFloat {
        let start = min(fit.points.first?.x ?? chartFrame.minX, chartFrame.minX)
        let end = max(fit.points.last?.x ?? chartFrame.maxX, chartFrame.maxX)
        return start + max(0.0, reveal) * (end - start)
    }

    func giftCurvePoint(lineIndex: Int, x: CGFloat) -> CGPoint? {
        guard lineIndex < self.giftState.fits.count, let first = self.giftState.fits[lineIndex].points.first, let last = self.giftState.fits[lineIndex].points.last else {
            return nil
        }
        let held = max(first.x, min(last.x, x))
        guard let y = self.giftState.fits[lineIndex].y(atX: held) else {
            return nil
        }
        return CGPoint(x: held, y: y)
    }

    func setGiftReveal(_ progress: CGFloat?) {
        self.giftState.reveal = progress.flatMap { $0 < 1.0 ? $0 : nil }
        self.setNeedsDisplay()
    }

    func drawGiftArea(context: CGContext, path: CGPath, points: [CGPoint], chartFrame: CGRect) {
        let amount = self.areaAnimator.current
        guard amount > 0.001, let first = points.first, let last = points.last else {
            return
        }
        let bottom = chartFrame.maxY
        let area = CGMutablePath()
        area.addPath(path)
        area.addLine(to: CGPoint(x: last.x, y: bottom))
        area.addLine(to: CGPoint(x: first.x, y: bottom))
        area.closeSubpath()
        context.saveGState()
        context.addPath(area)
        context.clip()
        let colors = [UIColor(white: 1.0, alpha: LinesChartRenderer.areaOpacity * amount).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: chartFrame.minY), end: CGPoint(x: 0.0, y: bottom), options: [])
        }
        context.restoreGState()
    }

    func playPulse() {
        guard self.giftRole == .main else {
            return
        }
        self.pulseAnimator.set(current: 0.0)
        self.pulseAnimator.animate(to: 1.0, duration: 1.3, timeFunction: .easeOut)
    }

    /// Unclipped dot at the last point, or at the stroke head during the draw-in.
    func drawGiftDot(context: CGContext, chartFrame: CGRect, alpha: CGFloat) {
        guard self.giftRole == .main, let fit = self.giftState.fits.first, let first = fit.points.first, let last = fit.points.last else {
            return
        }
        var alpha = alpha
        var point = last
        var radius: CGFloat = 3.5
        var glow: CGFloat = 0.7
        var blur: CGFloat = 8.0
        var pulse = self.pulseAnimator.current
        if let reveal = self.giftState.reveal {
            let edge = self.giftRevealEdge(reveal: reveal, fit: fit, chartFrame: chartFrame)
            if edge < last.x {
                guard edge >= first.x, let y = fit.y(atX: edge) else {
                    return
                }
                point = CGPoint(x: edge, y: y)
                let far = min(1.0, (last.x - edge) / 30.0)
                radius += 2.5 * far
                glow += 0.3 * far
                blur += 4.0 * far
                alpha *= min(1.0, reveal / 0.03)
                pulse = 1.0
            }
        }
        guard alpha > 0.0, point.x >= chartFrame.minX - 0.5, point.x <= chartFrame.maxX + 0.5 else {
            return
        }
        if pulse < 0.999 {
            let ring = 4.0 + 12.0 * pulse
            context.saveGState()
            context.setStrokeColor(UIColor(white: 1.0, alpha: 0.5 * (1.0 - pulse) * alpha).cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: CGRect(x: point.x - ring, y: point.y - ring, width: ring * 2.0, height: ring * 2.0))
            context.restoreGState()
        }
        context.saveGState()
        context.setShadow(offset: .zero, blur: blur, color: UIColor(white: 1.0, alpha: glow * alpha).cgColor)
        context.setFillColor(UIColor(white: 1.0, alpha: alpha).cgColor)
        context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2.0, height: radius * 2.0))
        context.restoreGState()
    }
}
