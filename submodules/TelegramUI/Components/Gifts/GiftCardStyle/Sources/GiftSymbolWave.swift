import Foundation
import UIKit
import Display

// Damped spring solved in closed form (e^(-a t) sin(w t)). Offsets go into the layer transform so they don't
// fight position/scale animations of the field.
final class GiftSymbolWave {
    private static let spread: Double = 1.8
    // Stiffness with mass 1, damping ratio 0.5.
    private static let stiffness: Double = 45.0
    private static let damping: Double = 0.5
    private static let push: Float = 8.0
    private static let peakScale: Float = 0.04
    private static let glow: Float = 0.15
    // Seconds after the front passes until the spring is below 0.1 pt.
    private static let settle: Double = 1.6

    private static let decay: Double = damping * stiffness.squareRoot()
    private static let frequency: Double = stiffness.squareRoot() * (1.0 - damping * damping).squareRoot()
    // Height of the first crest, so that push is the actual peak displacement.
    private static let crest: Double = {
        let t = atan(frequency / decay) / frequency
        return exp(-decay * t) * sin(frequency * t)
    }()

    static let maxCount = 1024
    // New waves are ignored beyond this; cutting a running wave would make symbols jump.
    private static let maxWaves = 4

    private struct Wave {
        let start: CFTimeInterval
        let arrival: [Float]
        let dirX: [Float]
        let dirY: [Float]
        var end: CFTimeInterval {
            return self.start + GiftSymbolWave.spread + GiftSymbolWave.settle
        }
    }

    private let layers: () -> [CALayer]
    private let baseScale: (Int) -> CGFloat
    private let baseOpacity: (Int) -> Float
    private var waves: [Wave] = []
    private var link: SharedDisplayLinkDriver.Link?
    private var count = 0

    init(layers: @escaping () -> [CALayer], baseScale: @escaping (Int) -> CGFloat = { _ in 1.0 }, baseOpacity: @escaping (Int) -> Float) {
        self.layers = layers
        self.baseScale = baseScale
        self.baseOpacity = baseOpacity
    }

    var isRunning: Bool {
        return !self.waves.isEmpty
    }

    private static func unitOffset(elapsed: Double) -> Double {
        if elapsed <= 0.0 {
            return 0.0
        }
        return exp(-decay * elapsed) * sin(frequency * elapsed) / crest
    }

    func start(origin: CGPoint, haptic: Bool = true) {
        guard !UIAccessibility.isReduceMotionEnabled, self.waves.count < GiftSymbolWave.maxWaves else {
            return
        }
        let layers = self.layers()
        guard !layers.isEmpty, layers.count <= GiftSymbolWave.maxCount else {
            return
        }
        if self.waves.isEmpty {
            self.count = layers.count
        } else if self.count != layers.count {
            return
        }
        var distances = [Float](repeating: 0.0, count: layers.count)
        var dirX = distances
        var dirY = distances
        for (i, layer) in layers.enumerated() {
            let dx = Float(layer.position.x - origin.x)
            let dy = Float(layer.position.y - origin.y)
            let distance = (dx * dx + dy * dy).squareRoot()
            distances[i] = distance
            if distance > 0.5 {
                dirX[i] = dx / distance
                dirY[i] = dy / distance
            } else {
                dirX[i] = 0.0
                dirY[i] = -1.0
            }
        }
        // Normalized so an origin outside the field doesn't delay the first symbol.
        let nearest = distances.min() ?? 0.0
        let span = max(1.0, (distances.max() ?? 1.0) - nearest)
        var arrival = distances
        for i in 0 ..< distances.count {
            arrival[i] = (distances[i] - nearest) / span * Float(GiftSymbolWave.spread)
        }
        self.waves.append(Wave(start: CACurrentMediaTime(), arrival: arrival, dirX: dirX, dirY: dirY))
        if haptic {
            HapticFeedback().impact(.light)
        }
        if self.link == nil {
            self.link = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] _ in
                self?.tick()
            })
        }
    }

    func layoutChanged(count: Int) {
        if self.isRunning && count != self.count {
            self.stop()
        }
    }

    func stop() {
        self.waves.removeAll()
        self.link?.invalidate()
        self.link = nil
        self.apply(offsets: nil)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        self.waves.removeAll { $0.end <= now }
        if self.waves.isEmpty {
            self.stop()
            return
        }
        self.apply(offsets: now)
    }

    private func apply(offsets time: CFTimeInterval?) {
        let layers = self.layers()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            CATransaction.commit()
        }
        guard let time, layers.count == self.count else {
            for (i, layer) in layers.enumerated() {
                let scale = self.baseScale(i)
                layer.transform = scale == 1.0 ? CATransform3DIdentity : CATransform3DMakeScale(scale, scale, 1.0)
                layer.opacity = self.baseOpacity(i)
            }
            return
        }
        for (i, layer) in layers.enumerated() {
            var x: Float = 0.0
            var y: Float = 0.0
            var swell: Float = 0.0
            var shine: Float = 0.0
            for wave in self.waves {
                let unit = Float(GiftSymbolWave.unitOffset(elapsed: time - wave.start - Double(wave.arrival[i])))
                if unit == 0.0 {
                    continue
                }
                x += wave.dirX[i] * GiftSymbolWave.push * unit
                y += wave.dirY[i] * GiftSymbolWave.push * unit
                swell += GiftSymbolWave.peakScale * unit
                // Brighten on the outward swing only, never dim.
                shine += GiftSymbolWave.glow * max(0.0, unit)
            }
            let transform = CATransform3DMakeTranslation(CGFloat(x), CGFloat(y), 0.0)
            let scale = CGFloat(1.0 + swell) * self.baseScale(i)
            layer.opacity = min(1.0, self.baseOpacity(i) * (1.0 + min(shine, GiftSymbolWave.glow)))
            layer.transform = CATransform3DScale(transform, scale, scale, 1.0)
        }
    }
}
