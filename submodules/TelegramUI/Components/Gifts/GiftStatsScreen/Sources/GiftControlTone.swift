import Foundation
import UIKit

// Control colour = the backdrop seen behind it, in OKLab, lightened by a fixed step with chroma capped.
// With Increase Contrast it is darkened until the white label reaches 4.5:1.
enum GiftControlTone {
    static let lightnessStep: Double = 0.06
    static let chromaCap: Double = 0.15
    static let increasedContrast: Double = 4.5
    static let darkestLightness: Double = 0.2
    private static let searchStep: Double = 0.005

    struct Tone {
        let color: UIColor
        let step: Double
        let contrast: Double
    }

    // The card's radial gradient is blended by the compositor in sRGB, so mix in sRGB here too.
    static func seen(inner: UIColor, outer: UIColor, outerShare: CGFloat) -> UIColor {
        let p = min(1.0, max(0.0, outerShare))
        var (ir, ig, ib, ia): (CGFloat, CGFloat, CGFloat, CGFloat) = (0.0, 0.0, 0.0, 0.0)
        var (or, og, ob, oa): (CGFloat, CGFloat, CGFloat, CGFloat) = (0.0, 0.0, 0.0, 0.0)
        inner.getRed(&ir, green: &ig, blue: &ib, alpha: &ia)
        outer.getRed(&or, green: &og, blue: &ob, alpha: &oa)
        return UIColor(red: ir + (or - ir) * p, green: ig + (og - ig) * p, blue: ib + (ob - ib) * p, alpha: 1.0)
    }

    static func tone(on backdrop: UIColor, label: UIColor = UIColor(white: 1.0, alpha: 0.85)) -> Tone {
        let base = backdrop.oklab
        let chroma = (base.a * base.a + base.b * base.b).squareRoot()
        let scale = chroma > GiftControlTone.chromaCap ? GiftControlTone.chromaCap / chroma : 1.0
        func make(_ step: Double) -> Tone {
            let color = base.with(lightness: min(1.0, max(0.0, base.l + step)), chromaScale: scale).color
            return Tone(color: color, step: step, contrast: GiftOKLab.contrast(label, over: color))
        }
        var step = GiftControlTone.lightnessStep
        var tone = make(step)
        if GiftStatsEnvironment.increaseContrast {
            while tone.contrast < GiftControlTone.increasedContrast && base.l + step - GiftControlTone.searchStep >= GiftControlTone.darkestLightness {
                step -= GiftControlTone.searchStep
                tone = make(step)
            }
        }
        return tone
    }

    private final class Cached {
        let tone: Tone

        init(_ tone: Tone) {
            self.tone = tone
        }
    }
    private static let cache = NSCache<NSString, Cached>()

    // Called on every layout; the share is rounded to 1/50 for the cache key.
    static func cachedTone(inner: UIColor, outer: UIColor, outerShare: CGFloat) -> Tone {
        let share = (min(1.0, max(0.0, outerShare)) * 50.0).rounded() / 50.0
        let key = "\(inner.rgbKey)|\(outer.rgbKey)|\(share)|\(GiftStatsEnvironment.increaseContrast)" as NSString
        if let cached = self.cache.object(forKey: key) {
            return cached.tone
        }
        let tone = self.tone(on: self.seen(inner: inner, outer: outer, outerShare: share))
        self.cache.setObject(Cached(tone), forKey: key)
        return tone
    }
}

private extension UIColor {
    var rgbKey: String {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0.0, 0.0, 0.0, 0.0)
        self.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.4f,%.4f,%.4f", r, g, b)
    }
}
