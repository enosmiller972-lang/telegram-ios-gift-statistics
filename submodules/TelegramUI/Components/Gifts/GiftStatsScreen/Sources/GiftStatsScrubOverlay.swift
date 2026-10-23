import Foundation
import UIKit
import Display
import GraphCore
import GiftStats

// Touch scrub overlay: guide line, point dots, tooltip
final class GiftStatsScrubOverlay: UIView {
    static let valueFont = Font.semibold(14.0)
    static let valueColor = GiftStatsLook.textColor
    private static let tooltipHeight: CGFloat = 46.0
    private static let tooltipGap: CGFloat = 14.0

    private let guide = CAShapeLayer()
    private var dots: [CALayer] = []
    private let tooltip = GiftFlatTonalView()
    private let dateLabel = UILabel()
    private let valuesLabel = UILabel()
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0.0

    private var guideX = GiftStatsSpring(0.0)
    private var tooltipX = GiftStatsSpring(0.0)
    private var fallbackYs: [CGFloat] = []
    private var isShown = false
    private var geometry: BaseChartController.ChartPlotGeometry?
    private var tooltipWidth: CGFloat = 0.0
    private var snappedX: CGFloat?

    var haptic: (() -> Void)?
    var join: ((NSAttributedString, NSAttributedString) -> NSAttributedString)?
    var curvePoint: ((Int, CGFloat) -> CGPoint?)?
    var showsDots = true
    var tooltipFlat: GiftFlat = .control
    var showsGuide = true
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.accessibilityElementsHidden = true
        self.guide.strokeColor = UIColor(white: 1.0, alpha: 0.55).cgColor
        self.guide.lineWidth = 1.0
        self.guide.opacity = 0.0
        self.layer.addSublayer(self.guide)
        self.addSubview(self.tooltip)
        self.tooltip.alpha = 0.0
        self.dateLabel.font = Font.regular(11.0)
        self.dateLabel.textColor = GiftStatsLook.secondaryTextColor
        self.valuesLabel.font = Font.semibold(14.0)
        self.valuesLabel.textColor = GiftStatsLook.textColor
        self.tooltip.addSubview(self.dateLabel)
        self.tooltip.addSubview(self.valuesLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.link?.invalidate()
    }

    private func makeDot(color: UIColor) -> CALayer {
        let dot = CALayer()
        dot.bounds = CGRect(x: 0.0, y: 0.0, width: 12.0, height: 12.0)
        dot.cornerRadius = 6.0
        dot.backgroundColor = UIColor.white.cgColor
        dot.borderColor = color.cgColor
        dot.borderWidth = 3.0
        dot.shadowColor = color.cgColor
        dot.shadowOpacity = 0.95
        dot.shadowRadius = 9.0
        dot.shadowOffset = .zero
        dot.shadowPath = CGPath(ellipseIn: dot.bounds, transform: nil)
        dot.opacity = 0.0
        return dot
    }

    func update(info: BaseChartController.ChartSelectionInfo?, geometry: BaseChartController.ChartPlotGeometry?, series: GiftStatsPriceSeries?, format: (Double) -> NSAttributedString, dateText: String) {
        guard let info, let geometry else {
            self.hide()
            return
        }
        self.geometry = geometry
        let frame = geometry.chartFrame
        if info.isNewPoint {
            self.haptic?()
        }
        while self.showsDots && self.dots.count < info.values.count {
            let dot = self.makeDot(color: info.colors[self.dots.count])
            self.layer.addSublayer(dot)
            self.dots.append(dot)
            self.fallbackYs.append(0.0)
        }
        let horizontal = geometry.horizontalRange
        let finger = max(0.0, min(1.0, info.fingerFraction))
        let time = horizontal.lowerBound + horizontal.upperBound.advanced(by: -horizontal.lowerBound) * finger
        let x = frame.minX + frame.width * finger
        let vertical = geometry.verticalRange
        var textValues: [NSAttributedString] = []
        for index in 0 ..< info.values.count {
            guard index < self.dots.count else {
                textValues.append(format(info.values[index]))
                continue
            }
            let value: Double
            if let series, index < series.allValues.count {
                value = series.interpolatedValue(at: Double(time), series: index)
            } else {
                value = info.values[index]
            }
            textValues.append(format(info.values[index]))
            let y = frame.maxY - frame.height * (CGFloat(value) - vertical.lowerBound) / max(0.0001, vertical.upperBound - vertical.lowerBound)
            self.fallbackYs[index] = y
        }
        self.guideX.value = x
        self.guideX.target = x
        self.guideX.velocity = 0.0
        self.snappedX = frame.minX + frame.width * (CGFloat(info.date.timeIntervalSince1970) - horizontal.lowerBound) / max(0.0001, horizontal.upperBound - horizontal.lowerBound)

        let isLeftHalf = x < self.bounds.width / 2.0
        self.dateLabel.text = dateText
        self.dateLabel.textColor = GiftStatsContrast.legible(GiftStatsLook.secondaryTextColor, over: [self.tooltipFlat.fill])
        var joined = NSAttributedString()
        let separatorAttributes: [NSAttributedString.Key: Any] = [.font: GiftStatsScrubOverlay.valueFont, .foregroundColor: GiftStatsScrubOverlay.valueColor]
        for (index, value) in textValues.enumerated() {
            if index == 0 {
                joined = value
            } else if let join = self.join {
                joined = join(joined, value)
            } else {
                let plain = NSMutableAttributedString(attributedString: joined)
                plain.append(NSAttributedString(string: " ", attributes: separatorAttributes))
                plain.append(value)
                joined = plain
            }
        }
        self.valuesLabel.attributedText = joined
        let dateSize = self.dateLabel.sizeThatFits(CGSize(width: 300.0, height: 20.0))
        let valuesSize = self.valuesLabel.sizeThatFits(CGSize(width: 300.0, height: 20.0))
        let width = ceil(max(dateSize.width, valuesSize.width)) + 24.0
        self.tooltipWidth = width
        let height = GiftStatsScrubOverlay.tooltipHeight
        self.tooltip.bounds = CGRect(x: 0.0, y: 0.0, width: width, height: height)
        self.tooltip.update(flat: self.tooltipFlat, radius: 14.0)
        self.dateLabel.frame = CGRect(x: 12.0, y: 6.0, width: ceil(dateSize.width), height: ceil(dateSize.height))
        self.valuesLabel.frame = CGRect(x: 12.0, y: 6.0 + ceil(dateSize.height) + 1.0, width: ceil(valuesSize.width), height: ceil(valuesSize.height))
        let gap = GiftStatsScrubOverlay.tooltipGap
        let targetLeft = isLeftHalf ? x + gap : x - gap - width
        self.tooltipX.target = max(6.0, min(self.bounds.width - width - 6.0, targetLeft))
        // Reduce motion: snap immediately
        if GiftStatsEnvironment.reduceMotion {
            self.tooltipX.value = self.tooltipX.target
            self.tooltipX.velocity = 0.0
        }

        if !self.isShown {
            self.isShown = true
            self.tooltipX.value = self.tooltipX.target
            self.tooltip.layer.removeAllAnimations()
            self.tooltip.alpha = 1.0
            if GiftStatsEnvironment.reduceMotion {
                self.tooltip.transform = .identity
            } else {
                self.tooltip.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
                UIView.animate(withDuration: 0.5, delay: 0.0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.8, options: [.allowUserInteraction], animations: {
                    self.tooltip.transform = .identity
                })
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.guide.opacity = self.showsGuide ? 1.0 : 0.0
            for dot in self.dots {
                dot.opacity = 1.0
            }
            CATransaction.commit()
            self.guide.path = {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0.0, y: frame.minY))
                path.addLine(to: CGPoint(x: 0.0, y: frame.maxY))
                return path
            }()
        }
        self.apply()
        self.startLink()
    }

    private func hide() {
        guard self.isShown else {
            return
        }
        self.isShown = false
        if let snappedX = self.snappedX {
            self.guideX.target = snappedX
            if GiftStatsEnvironment.reduceMotion {
                self.guideX.value = snappedX
                self.guideX.velocity = 0.0
            }
        }
        UIView.animate(withDuration: GiftStatsEnvironment.reduceMotion ? 0.15 : 0.28, delay: 0.0, options: [.curveEaseOut, .allowUserInteraction], animations: {
            self.tooltip.alpha = 0.0
            if !GiftStatsEnvironment.reduceMotion {
                self.tooltip.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            }
        })
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        self.guide.opacity = 0.0
        for dot in self.dots {
            dot.opacity = 0.0
        }
        CATransaction.commit()
    }

    private func apply() {
        guard let frame = self.geometry?.chartFrame else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var guideX = self.guideX.value
        if let first = self.curvePoint?(0, guideX) {
            guideX = first.x
        }
        self.guide.position = CGPoint(x: guideX, y: 0.0)
        for (index, dot) in self.dots.enumerated() where index < self.fallbackYs.count {
            if let point = self.curvePoint?(index, self.guideX.value) {
                dot.position = point
            } else {
                dot.position = CGPoint(x: self.guideX.value, y: self.fallbackYs[index])
            }
        }
        CATransaction.commit()
        let y: CGFloat = frame.minY + 2.0
        self.tooltip.center = CGPoint(x: self.tooltipX.value + self.tooltipWidth / 2.0, y: y + GiftStatsScrubOverlay.tooltipHeight / 2.0)
    }

    private func startLink() {
        if self.link == nil {
            let link = CADisplayLink(target: self, selector: #selector(self.tick))
            self.lastTick = CACurrentMediaTime()
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    private func stopLink() {
        self.link?.invalidate()
        self.link = nil
    }

    // Invalidate display link when removed from window
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            self.stopLink()
        }
    }

    // Resume display link if springs are still active
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if self.window != nil && self.link == nil && (self.isShown || !self.guideX.isResting || !self.tooltipX.isResting) {
            self.startLink()
        }
    }

    @objc private func tick() {
        if self.window == nil {
            self.stopLink()
            return
        }
        let now = CACurrentMediaTime()
        let dt = CGFloat(now - self.lastTick)
        self.lastTick = now
        self.guideX.step(dt)
        self.tooltipX.step(dt)
        self.apply()
        if !self.isShown && self.guideX.isResting && self.tooltipX.isResting {
            self.stopLink()
        }
    }
}
