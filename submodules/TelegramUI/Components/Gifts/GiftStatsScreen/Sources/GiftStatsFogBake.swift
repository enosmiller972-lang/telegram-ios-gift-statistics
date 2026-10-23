import Foundation
import UIKit
import CoreImage

/// A static image of the fogged row for the morph, since a snapshot cannot sit under a live blur. Blends a few
/// Gaussian-blurred copies per pixel row, from sharp at the top to `GiftStatsFogView.maxBlurRadius` at the bottom.
enum GiftStatsFogBake {
    private static let steps = 4
    /// Gaussian sigma (pt) per unit of fog blur radius, matched against the live fog.
    static let sigmaPerRadius: CGFloat = 1.67

    /// Synchronous fallback for when `GiftStatsFogBaker` has no image ready.
    static func picture(of row: UIView) -> UIImageView? {
        guard let flat = self.flatImage(of: row), let baked = self.bake(flat) else {
            return nil
        }
        return self.view(of: baked, size: row.bounds.size)
    }

    /// Main thread only.
    static func flatImage(of row: UIView) -> UIImage? {
        return (GiftMorphCapture.picture(of: row) as? UIImageView)?.image
    }

    static func view(of image: UIImage, size: CGSize) -> UIImageView {
        let picture = UIImageView(image: image)
        picture.frame = CGRect(origin: .zero, size: size)
        return picture
    }

    /// Touches no views, safe on any queue.
    static func bake(_ image: UIImage) -> UIImage? {
        guard let source = image.cgImage else {
            return nil
        }
        let width = source.width
        let height = source.height
        let rowBytes = width * 4
        let count = rowBytes * height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let levels = UnsafeMutablePointer<UInt8>.allocate(capacity: count * (self.steps + 1))
        defer {
            levels.deallocate()
        }
        guard self.draw(source, into: levels, width: width, height: height, colorSpace: colorSpace) else {
            return nil
        }
        let base = CIImage(cgImage: source)
        for step in 1 ... self.steps {
            let radius = GiftStatsFogView.maxBlurRadius * CGFloat(step) / CGFloat(self.steps)
            let sigma = radius * self.sigmaPerRadius * image.scale
            guard let blurred = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: base.clampedToExtent(), kCIInputRadiusKey: sigma])?.outputImage?.cropped(to: base.extent),
                  let cgImage = GiftStatsImageContext.shared.createCGImage(blurred, from: base.extent, format: .RGBA8, colorSpace: colorSpace),
                  self.draw(cgImage, into: levels + count * step, width: width, height: height, colorSpace: colorSpace) else {
                return nil
            }
        }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = context.data else {
            return nil
        }
        let result = data.assumingMemoryBound(to: UInt8.self)
        // Each pixel row mixes the two blur levels nearest to its height.
        for y in 0 ..< height {
            let position = (CGFloat(y) + 0.5) / CGFloat(height) * CGFloat(self.steps)
            let lower = min(self.steps - 1, Int(position))
            let mix = position - CGFloat(lower)
            let weightUpper = Int(round(mix * 256.0))
            let weightLower = 256 - weightUpper
            let offset = y * rowBytes
            let from = levels + count * lower + offset
            let to = levels + count * (lower + 1) + offset
            let out = result + y * context.bytesPerRow
            for index in 0 ..< rowBytes {
                let value = (Int(from[index]) * weightLower + Int(to[index]) * weightUpper + 128) >> 8
                out[index] = UInt8(min(255, value))
            }
        }
        guard let output = context.makeImage() else {
            return nil
        }
        return UIImage(cgImage: output, scale: image.scale, orientation: .up)
    }

    private static func draw(_ image: CGImage, into pointer: UnsafeMutablePointer<UInt8>, width: Int, height: Int, colorSpace: CGColorSpace) -> Bool {
        guard let context = CGContext(data: pointer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return false
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.clear(rect)
        context.draw(image, in: rect)
        return true
    }
}
