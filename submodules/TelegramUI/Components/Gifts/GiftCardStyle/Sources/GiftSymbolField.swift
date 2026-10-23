import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import AnimationCache
import MultiAnimationRenderer
import EmojiTextAttachmentView
import LokiRng

private final class GiftSymbolTarget: MultiAnimationRenderTarget {
    var updated: (() -> Void)?

    override func transitionToContents(_ contents: AnyObject, didLoop: Bool) {
        self.contents = contents
        self.updated?()
    }
}

// Same ring layout and LokiRng seed as PeerInfoCoverComponent, so the inner rings match the gift screen header.
public final class GiftSymbolFieldView: UIView {
    private static let baseDistance: CGFloat = 72.0
    private static let rowDistance: CGFloat = 28.0
    private static let itemSize: CGFloat = 26.0

    private let target = GiftSymbolTarget()
    private var fileId: Int64?
    private var disposable: Disposable?
    private var itemLayers: [CALayer] = []
    private var tintedImage: CGImage?
    private var color: UIColor = .clear
    private var applied: (size: CGSize, center: CGPoint, firstRow: Int, alpha: CGFloat)?
    private var appliedFade: CGSize?
    private var rest: [(position: CGPoint, opacity: Float, distance: CGFloat)] = []
    // 0 = symbols at rest, 1 = all sunk into the gift.
    private var flow: CGFloat?
    private var flowScales: [CGFloat] = []
    private var flowOpacities: [Float] = []
    private lazy var symbolWave = GiftSymbolWave(layers: { [weak self] in
        return self?.itemLayers ?? []
    }, baseScale: { [weak self] index in
        guard let self, index < self.flowScales.count else {
            return 1.0
        }
        return self.flowScales[index]
    }, baseOpacity: { [weak self] index in
        guard let self else {
            return 1.0
        }
        if index < self.flowOpacities.count {
            return self.flowOpacities[index]
        }
        return index < self.rest.count ? self.rest[index].opacity : 1.0
    })

    override public init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.target.updated = { [weak self] in
            self?.imageUpdated()
        }
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.disposable?.dispose()
    }

    private func imageUpdated() {
        guard let contents = self.target.contents else {
            return
        }
        let cgImage = contents as! CGImage
        self.tintedImage = generateTintedImage(image: UIImage(cgImage: cgImage), color: self.color)?.cgImage
        for layer in self.itemLayers {
            layer.contents = self.tintedImage
        }
    }

    private static let flowStagger: CGFloat = 0.45
    private static let flowEndScale: CGFloat = 0.3
    // Symbols are hidden within flowHole of the centre and fully visible beyond flowRim.
    private static let flowHole: CGFloat = 26.0
    private static let flowRim: CGFloat = 62.0

    // Pure function of progress (driven by the morph clock); nil restores the rest layout.
    public func setFlow(_ progress: CGFloat?) {
        self.flow = progress
        self.applyFlow()
    }

    private static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ value: CGFloat) -> CGFloat {
        let t = min(1.0, max(0.0, (value - edge0) / (edge1 - edge0)))
        return t * t * (3.0 - 2.0 * t)
    }

    private func applyFlow() {
        guard self.rest.count == self.itemLayers.count, let center = self.applied?.center else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            CATransaction.commit()
        }
        guard let progress = self.flow else {
            self.flowScales = [CGFloat](repeating: 1.0, count: self.itemLayers.count)
            self.flowOpacities = []
            for (i, layer) in self.itemLayers.enumerated() {
                layer.position = self.rest[i].position
                if !self.symbolWave.isRunning {
                    layer.opacity = self.rest[i].opacity
                    layer.transform = CATransform3DIdentity
                }
            }
            return
        }
        var nearest = CGFloat.greatestFiniteMagnitude
        var farthest: CGFloat = 0.0
        for item in self.rest {
            nearest = min(nearest, item.distance)
            farthest = max(farthest, item.distance)
        }
        let span = max(1.0, farthest - nearest)
        let take = 1.0 - GiftSymbolFieldView.flowStagger
        if self.flowScales.count != self.itemLayers.count {
            self.flowScales = [CGFloat](repeating: 1.0, count: self.itemLayers.count)
        }
        if self.flowOpacities.count != self.itemLayers.count {
            self.flowOpacities = [Float](repeating: 0.0, count: self.itemLayers.count)
        }
        for (i, layer) in self.itemLayers.enumerated() {
            let item = self.rest[i]
            let delay = (item.distance - nearest) / span * GiftSymbolFieldView.flowStagger
            let u = min(1.0, max(0.0, (progress - delay) / take))
            let e = pow(u, 1.8)
            let dx = item.position.x - center.x
            let dy = item.position.y - center.y
            let distance = max(1.0, item.distance)
            let bow = distance * 0.14 * sin(CGFloat.pi * e)
            let position = CGPoint(
                x: center.x + dx * (1.0 - e) - dy / distance * bow,
                y: center.y + dy * (1.0 - e) + dx / distance * bow
            )
            let scale = 1.0 - (1.0 - GiftSymbolFieldView.flowEndScale) * e
            let toCentre = hypot(position.x - center.x, position.y - center.y)
            let reach = 1.0 - GiftSymbolFieldView.smoothstep(0.5, 1.0, u)
            let round = GiftSymbolFieldView.smoothstep(GiftSymbolFieldView.flowHole, GiftSymbolFieldView.flowRim, toCentre)
            layer.position = position
            let opacity = item.opacity * Float(reach * round)
            self.flowOpacities[i] = opacity
            self.flowScales[i] = scale
            if !self.symbolWave.isRunning {
                layer.opacity = opacity
                layer.transform = CATransform3DMakeScale(scale, scale, 1.0)
            }
        }
    }

    public func startWave(from point: CGPoint, haptic: Bool = true) {
        self.symbolWave.start(origin: point, haptic: haptic)
    }

    // fade: radii of the ellipse at which symbols reach zero opacity.
    public func update(context: AccountContext, file: TelegramMediaFile?, color: UIColor, center: CGPoint, size: CGSize, fade: CGSize, firstRow: Int = 0) {
        if self.color != color {
            self.color = color
            self.imageUpdated()
        }
        if let file, self.fileId != file.fileId.id {
            self.fileId = file.fileId.id
            self.disposable?.dispose()
            let itemId = file.resource.id.stringRepresentation
            if !context.animationRenderer.loadFirstFrameSynchronously(target: self.target, cache: context.animationCache, itemId: itemId, size: CGSize(width: 96.0, height: 96.0)) {
                self.disposable = context.animationRenderer.loadFirstFrame(
                    target: self.target,
                    cache: context.animationCache,
                    itemId: itemId,
                    size: CGSize(width: 96.0, height: 96.0),
                    fetch: animationCacheFetchFile(
                        postbox: context.account.postbox,
                        userLocation: .other,
                        userContentType: .sticker,
                        resource: .media(media: .standalone(media: file), resource: file.resource),
                        type: AnimationCacheAnimationType(file: file),
                        keyframeOnly: false,
                        customColor: .white,
                        lottieSettings: context.lottieRenderingSettings
                    ),
                    completion: { _, _ in }
                )
            } else {
                self.imageUpdated()
            }
        }
        let alpha = fade.width + fade.height
        if let applied = self.applied, applied.size == size, applied.center == center, applied.firstRow == firstRow, applied.alpha == alpha, self.appliedFade == fade {
            return
        }
        self.applied = (size, center, firstRow, alpha)
        self.appliedFade = fade
        var restItems: [(position: CGPoint, opacity: Float, distance: CGFloat)] = []

        let rng = LokiRng(seed0: 123, seed1: 0, seed2: 0)
        var count = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var row = 0
        while true {
            let distance = GiftSymbolFieldView.baseDistance + CGFloat(row) * GiftSymbolFieldView.rowDistance
            if distance > max(fade.width, fade.height) + GiftSymbolFieldView.itemSize {
                break
            }
            let step = CGFloat.pi * 2.0 / 6.0
            for i in 0 ..< 6 {
                var angle = -CGFloat.pi * 0.5 + CGFloat(i) * step
                if row % 2 != 0 {
                    angle += step * 0.5
                }
                let scale = 0.7 + CGFloat(rng.next()) * 0.3
                guard row >= firstRow else {
                    continue
                }
                let offset = CGPoint(x: cos(angle) * distance, y: sin(angle) * distance)
                let t = sqrt(pow(offset.x / max(1.0, fade.width), 2.0) + pow(offset.y / max(1.0, fade.height), 2.0))
                // As in PeerInfoCoverComponent: a 0.6 radial gradient falling linearly to the edge, under a 0.8 mask.
                let opacity = 0.48 * (1.0 - t)
                if opacity <= 0.01 {
                    continue
                }
                let position = CGPoint(x: center.x + offset.x, y: center.y + offset.y)
                let side = floor(GiftSymbolFieldView.itemSize * scale)
                let layer: CALayer
                if count < self.itemLayers.count {
                    layer = self.itemLayers[count]
                } else {
                    layer = CALayer()
                    layer.contents = self.tintedImage
                    self.layer.addSublayer(layer)
                    self.itemLayers.append(layer)
                }
                // Not frame: the wave may have a transform applied.
                layer.bounds = CGRect(x: 0.0, y: 0.0, width: side, height: side)
                layer.position = position
                layer.opacity = Float(opacity)
                restItems.append((position, Float(opacity), hypot(offset.x, offset.y)))
                count += 1
            }
            row += 1
        }
        while self.itemLayers.count > count {
            self.itemLayers.removeLast().removeFromSuperlayer()
        }
        CATransaction.commit()
        self.rest = restItems
        if self.flow != nil {
            self.applyFlow()
        }
        self.symbolWave.layoutChanged(count: count)
    }
}
