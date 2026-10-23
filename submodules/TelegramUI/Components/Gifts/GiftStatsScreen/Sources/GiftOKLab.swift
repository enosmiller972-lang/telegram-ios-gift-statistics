import Foundation
import UIKit

// OKLab (Bjorn Ottosson): l in 0...1; chroma is the length of (a, b), hue its angle.
struct GiftOKLab: Equatable {
    var l: Double
    var a: Double
    var b: Double
    var alpha: Double = 1.0

    init(l: Double, a: Double, b: Double, alpha: Double = 1.0) {
        self.l = l
        self.a = a
        self.b = b
        self.alpha = alpha
    }

    private static func linear(_ c: Double) -> Double {
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func gamma(_ c: Double) -> Double {
        return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055
    }

    init(color: UIColor) {
        var (r, g, b, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0.0, 0.0, 0.0, 0.0)
        color.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        let lr = GiftOKLab.linear(Double(r))
        let lg = GiftOKLab.linear(Double(g))
        let lb = GiftOKLab.linear(Double(b))
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        self.init(
            l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
            alpha: Double(alpha)
        )
    }

    private func linearRGB(chroma: Double) -> (Double, Double, Double) {
        let a = self.a * chroma
        let b = self.b * chroma
        let l = pow(self.l + 0.3963377774 * a + 0.2158037573 * b, 3.0)
        let m = pow(self.l - 0.1055613458 * a - 0.0638541728 * b, 3.0)
        let s = pow(self.l - 0.0894841775 * a - 1.2914855480 * b, 3.0)
        return (
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }

    private static func isInGamut(_ rgb: (Double, Double, Double)) -> Bool {
        let tolerance = 0.0001
        return [rgb.0, rgb.1, rgb.2].allSatisfy { $0 >= -tolerance && $0 <= 1.0 + tolerance }
    }

    // Out-of-gamut colours lose chroma (keeping lightness and hue) instead of clipping a channel.
    var color: UIColor {
        var chroma = 1.0
        if !GiftOKLab.isInGamut(self.linearRGB(chroma: 1.0)) {
            var low = 0.0
            var high = 1.0
            for _ in 0 ..< 20 {
                let mid = (low + high) / 2.0
                if GiftOKLab.isInGamut(self.linearRGB(chroma: mid)) {
                    low = mid
                } else {
                    high = mid
                }
            }
            chroma = low
        }
        let rgb = self.linearRGB(chroma: chroma)
        let clamp = { (value: Double) -> CGFloat in
            return CGFloat(GiftOKLab.gamma(min(1.0, max(0.0, value))))
        }
        return UIColor(red: clamp(rgb.0), green: clamp(rgb.1), blue: clamp(rgb.2), alpha: CGFloat(self.alpha))
    }

    func with(lightness l: Double, chromaScale: Double = 1.0) -> GiftOKLab {
        return GiftOKLab(l: l, a: self.a * chromaScale, b: self.b * chromaScale, alpha: self.alpha)
    }

    func mixed(with other: GiftOKLab, _ p: Double) -> GiftOKLab {
        return GiftOKLab(l: self.l + (other.l - self.l) * p, a: self.a + (other.a - self.a) * p, b: self.b + (other.b - self.b) * p, alpha: self.alpha + (other.alpha - self.alpha) * p)
    }

    // WCAG 2.x relative luminance.
    static func luminance(of color: UIColor) -> Double {
        var (r, g, b, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0.0, 0.0, 0.0, 0.0)
        color.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        return 0.2126 * GiftOKLab.linear(Double(r)) + 0.7152 * GiftOKLab.linear(Double(g)) + 0.0722 * GiftOKLab.linear(Double(b))
    }

    // WCAG contrast ratio; a translucent foreground is composited over the background first.
    static func contrast(_ foreground: UIColor, over background: UIColor) -> Double {
        let flat = background.withAlphaComponent(1.0)
        let shown = foreground.cgColor.alpha < 0.999 ? flat.mixedSRGB(with: foreground.withAlphaComponent(1.0), alpha: foreground.cgColor.alpha) : foreground
        let a = GiftOKLab.luminance(of: shown)
        let b = GiftOKLab.luminance(of: flat)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

extension UIColor {
    var oklab: GiftOKLab {
        return GiftOKLab(color: self)
    }

    // A fully transparent side takes the other's colour, so the mix doesn't pass through grey.
    func mixedOKLab(with other: UIColor, alpha: CGFloat) -> UIColor {
        var from = self.oklab
        var to = other.oklab
        if from.alpha < 0.001 {
            from = GiftOKLab(l: to.l, a: to.a, b: to.b, alpha: 0.0)
        }
        if to.alpha < 0.001 {
            to = GiftOKLab(l: from.l, a: from.a, b: from.b, alpha: 0.0)
        }
        return from.mixed(with: to, Double(alpha)).color
    }

    fileprivate func mixedSRGB(with other: UIColor, alpha: CGFloat) -> UIColor {
        var (ar, ag, ab, aa): (CGFloat, CGFloat, CGFloat, CGFloat) = (0.0, 0.0, 0.0, 0.0)
        var (br, bg, bb, ba): (CGFloat, CGFloat, CGFloat, CGFloat) = (0.0, 0.0, 0.0, 0.0)
        self.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        other.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * alpha, green: ag + (bg - ag) * alpha, blue: ab + (bb - ab) * alpha, alpha: 1.0)
    }
}
