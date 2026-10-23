import Foundation
import CoreImage

/// One shared, thread-safe CIContext for digit blur and fog baking, so GPU resources are built only once.
enum GiftStatsImageContext {
    static let shared = CIContext(options: [.useSoftwareRenderer: false])

    private static var isWarmedUp = false

    /// Runs a tiny blur in the background so the first real use does not pay for setup. Call on the main thread.
    static func prewarm() {
        guard !self.isWarmedUp else {
            return
        }
        self.isWarmedUp = true
        DispatchQueue.global(qos: .userInitiated).async {
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            let image = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5)).cropped(to: CGRect(x: 0.0, y: 0.0, width: 64.0, height: 32.0))
            let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: 3.0).cropped(to: image.extent).transformed(by: CGAffineTransform(scaleX: 2.0, y: 2.0))
            _ = GiftStatsImageContext.shared.createCGImage(blurred, from: blurred.extent, format: .RGBA8, colorSpace: colorSpace)
        }
    }
}
