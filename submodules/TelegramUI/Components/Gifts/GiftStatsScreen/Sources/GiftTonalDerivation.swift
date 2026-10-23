import Foundation
import UIKit
import GiftStats

// Panel colours in OKLab with WCAG contrast checks. On a gift backdrop the panel mirrors how the Craft tint relates to
// the Craft page: lightness +/- panelStep, chroma x panelChroma, same hue. Lighter if white values still pass,
// otherwise darker; label alphas are raised first, then the panel darkens within darkestShare/maximumDarkStep.
struct GiftTonalDerivation: Equatable {
    struct Targets: Equatable {
        var value: Double
        var label: Double
        var dim: Double
        var button: Double
        var labelAlphaLimit: CGFloat
        var dimAlphaLimit: CGFloat

        static let craft = Targets(value: 7.0, label: 4.4, dim: 3.0, button: 4.5, labelAlphaLimit: 0.72, dimAlphaLimit: 0.60)
        static let gift = Targets(value: 4.5, label: 3.0, dim: 2.5, button: 3.0, labelAlphaLimit: 0.85, dimAlphaLimit: 0.70)
    }

    // Backdrop pattern and text colours from the server.
    struct Native: Equatable {
        var pattern: UIColor
        var text: UIColor
    }

    static let nativeShare: CGFloat = 0.62
    static let nativeLabelAlpha: CGFloat = 0.85
    static let nativeDimAlpha: CGFloat = 0.60
    static let nativeControlStep: Double = 0.04
    static let nativeButtonStep: Double = 0.04
    // Keeps very dark pattern colours (e.g. Onyx Black) from punching a hole.
    static let nativeMaxDarkStep: Double = 0.14
    static let nativeLift: Double = 0.045
    static let nativeLiftStep: Double = 0.005

    // Measured Craft tint vs. page: lightness +0.117/+0.133, chroma x1.126/x1.237 (top/bottom).
    static let panelStep: Double = 0.125
    static let panelChroma: Double = 1.18
    static let maximumDarkStep: Double = panelStep * 1.5
    static let darkestShare: Double = 0.8
    // A full panelStep made tiles near-black on light backdrops.
    static let controlStep: Double = panelStep * 0.4
    static let buttonStep: Double = 0.04
    static let craftButtonStep: Double = 0.07
    static let labelAlpha: CGFloat = 0.60
    static let dimAlpha: CGFloat = 0.45
    private static let darkeningStep: Double = 0.005

    let panel: UIColor
    let control: UIColor
    let button: UIColor
    let label: UIColor
    let dim: UIColor

    // isFlat: source is the Craft tint, used as is for panel and controls.
    init(source: UIColor, isFlat: Bool, native: Native? = nil) {
        let base = source.oklab
        if isFlat {
            self = GiftTonalDerivation.attempt(base: base, lightness: base.l, direction: 0.0, targets: .craft, native: nil, force: true)!
            return
        }
        if let native {
            self = GiftTonalDerivation.native(source: source, native: native)
            return
        }
        let targets = Targets.gift
        if let lighter = GiftTonalDerivation.attempt(base: base, lightness: min(1.0, base.l + GiftTonalDerivation.panelStep), direction: 1.0, targets: targets, native: nil, force: false) {
            self = lighter
            return
        }
        let start = base.l - GiftTonalDerivation.panelStep
        let floor = min(start, max(base.l * GiftTonalDerivation.darkestShare, base.l - GiftTonalDerivation.maximumDarkStep))
        var lightness = start
        var result: GiftTonalDerivation?
        while result == nil {
            let isLast = lightness <= floor + 0.000001
            result = GiftTonalDerivation.attempt(base: base, lightness: lightness, direction: -1.0, targets: targets, native: nil, force: isLast)
            lightness = max(floor, lightness - GiftTonalDerivation.darkeningStep)
        }
        self = result!
    }

    private static let cacheLock = NSLock()
    private static var cache: [String: GiftTonalDerivation] = [:]

    static func make(source: UIColor, isFlat: Bool, native: Native? = nil) -> GiftTonalDerivation {
        let key = "\(source.hashKey)|\(isFlat)|\(native?.pattern.hashKey ?? "")|\(native?.text.hashKey ?? "")"
        GiftTonalDerivation.cacheLock.lock()
        let cached = GiftTonalDerivation.cache[key]
        GiftTonalDerivation.cacheLock.unlock()
        if let cached {
            return cached
        }
        let made = GiftTonalDerivation(source: source, isFlat: isFlat, native: native)
        GiftTonalDerivation.cacheLock.lock()
        GiftTonalDerivation.cache[key] = made
        GiftTonalDerivation.cacheLock.unlock()
        return made
    }

    private init(panel: UIColor, control: UIColor, button: UIColor, label: UIColor, dim: UIColor) {
        self.panel = panel
        self.control = control
        self.button = button
        self.label = label
        self.dim = dim
    }

    private static func alpha(of ink: UIColor, from start: CGFloat, to limit: CGFloat, minimum: Double, surfaces: [UIColor]) -> CGFloat? {
        var alpha = start
        while alpha <= limit + 0.0001 {
            let shown = ink.withAlphaComponent(alpha)
            if surfaces.allSatisfy({ GiftOKLab.contrast(shown, over: $0) >= minimum }) {
                return alpha
            }
            alpha += 0.02
        }
        return nil
    }

    // direction: +1 lighter, -1 darker, 0 flat Craft look.
    private static func attempt(base: GiftOKLab, lightness: Double, direction: Double, targets: Targets, native: Native?, force: Bool) -> GiftTonalDerivation? {
        let isFlat = direction == 0.0
        let chroma = isFlat ? 1.0 : GiftTonalDerivation.panelChroma
        let panel = base.with(lightness: lightness, chromaScale: chroma).color
        let control = isFlat ? panel : base.with(lightness: lightness + direction * GiftTonalDerivation.controlStep, chromaScale: chroma).color
        let button = base.with(lightness: isFlat ? lightness + GiftTonalDerivation.craftButtonStep : lightness + direction * GiftTonalDerivation.controlStep + direction * GiftTonalDerivation.buttonStep, chromaScale: chroma).color
        let white = UIColor.white
        let isValueOK = GiftOKLab.contrast(white, over: control) >= targets.value && GiftOKLab.contrast(white, over: panel) >= targets.value
        let isButtonOK = GiftOKLab.contrast(white, over: button) >= targets.button
        let labelSurfaces = [panel, control]
        let label = GiftTonalDerivation.alpha(of: white, from: GiftTonalDerivation.labelAlpha, to: targets.labelAlphaLimit, minimum: targets.label, surfaces: labelSurfaces)
        let dim = GiftTonalDerivation.alpha(of: white, from: GiftTonalDerivation.dimAlpha, to: targets.dimAlphaLimit, minimum: targets.dim, surfaces: [panel])
        if !force && !(isValueOK && isButtonOK && label != nil && dim != nil) {
            return nil
        }
        // When forced, alphas stay at their limits; fall back to the backdrop text colour if available.
        var labelColor = white.withAlphaComponent(label ?? targets.labelAlphaLimit)
        var dimColor = white.withAlphaComponent(dim ?? targets.dimAlphaLimit)
        if (label == nil || dim == nil), let text = native?.text {
            labelColor = text.withAlphaComponent(GiftTonalDerivation.alpha(of: text, from: GiftTonalDerivation.labelAlpha, to: targets.labelAlphaLimit, minimum: targets.label, surfaces: labelSurfaces) ?? targets.labelAlphaLimit)
            dimColor = text.withAlphaComponent(GiftTonalDerivation.alpha(of: text, from: GiftTonalDerivation.dimAlpha, to: targets.dimAlphaLimit, minimum: targets.dim, surfaces: [panel]) ?? targets.dimAlphaLimit)
        }
        return GiftTonalDerivation(panel: panel, control: control, button: button, label: labelColor, dim: dimColor)
    }

    // Panel = backdrop mixed with nativeShare of the pattern colour, lifted by nativeLift; labels use the backdrop text colour.
    private static func native(source: UIColor, native: Native) -> GiftTonalDerivation {
        var base = source.mixedOKLab(with: native.pattern, alpha: GiftTonalDerivation.nativeShare).oklab
        let sourceLightness = source.oklab.l
        let floor = max(sourceLightness - GiftTonalDerivation.nativeMaxDarkStep, sourceLightness * GiftTonalDerivation.darkestShare)
        if base.l < floor {
            base = base.with(lightness: floor)
        }
        let white = UIColor.white
        // The lift may not drop contrast below the unlifted panel's (capped at the targets).
        let rest = GiftTonalDerivation.nativeSurfaces(base: base, lift: 0.0)
        let valueNeeded = min(GiftTonalDerivation.Targets.gift.value, GiftOKLab.contrast(white, over: rest.control), GiftOKLab.contrast(white, over: rest.panel))
        let labelNeeded = min(GiftTonalDerivation.Targets.gift.label, GiftOKLab.contrast(native.text.withAlphaComponent(GiftTonalDerivation.nativeLabelAlpha), over: rest.control), GiftOKLab.contrast(native.text.withAlphaComponent(GiftTonalDerivation.nativeLabelAlpha), over: rest.panel))
        var lift = GiftTonalDerivation.nativeLift
        var surfaces = GiftTonalDerivation.nativeSurfaces(base: base, lift: lift)
        var labelAlpha = GiftTonalDerivation.nativeLabelAlpha
        while lift > 0.0 {
            surfaces = GiftTonalDerivation.nativeSurfaces(base: base, lift: lift)
            if GiftOKLab.contrast(white, over: surfaces.control) >= valueNeeded && GiftOKLab.contrast(white, over: surfaces.panel) >= valueNeeded {
                // Raise label alpha first; reduce the lift only if that isn't enough.
                if let reached = GiftTonalDerivation.alpha(of: native.text, from: GiftTonalDerivation.nativeLabelAlpha, to: 1.0, minimum: labelNeeded, surfaces: [surfaces.panel, surfaces.control]) {
                    labelAlpha = reached
                    break
                }
            }
            lift = max(0.0, lift - GiftTonalDerivation.nativeLiftStep)
            if lift == 0.0 {
                surfaces = rest
                labelAlpha = GiftTonalDerivation.nativeLabelAlpha
            }
        }
        return GiftTonalDerivation(
            panel: surfaces.panel,
            control: surfaces.control,
            button: surfaces.button,
            label: native.text.withAlphaComponent(labelAlpha),
            dim: native.text.withAlphaComponent(GiftTonalDerivation.nativeDimAlpha)
        )
    }

    private static func nativeSurfaces(base: GiftOKLab, lift: Double) -> (panel: UIColor, control: UIColor, button: UIColor) {
        let lightness = min(1.0, base.l + lift)
        return (
            base.with(lightness: lightness).color,
            base.with(lightness: min(1.0, lightness + GiftTonalDerivation.nativeControlStep)).color,
            base.with(lightness: min(1.0, lightness + GiftTonalDerivation.nativeControlStep + GiftTonalDerivation.nativeButtonStep)).color
        )
    }
}

private extension UIColor {
    var hashKey: String {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0.0, 0.0, 0.0, 0.0)
        self.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.4f,%.4f,%.4f,%.3f", r, g, b, a)
    }
}
