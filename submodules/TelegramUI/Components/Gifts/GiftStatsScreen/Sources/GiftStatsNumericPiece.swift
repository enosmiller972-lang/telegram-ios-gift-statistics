import Foundation
import UIKit
import CoreImage
import Display

/// A digit or a run of other characters in `GiftStatsNumericTextView`. UIKit cannot animate a blur filter publicly,
/// so the change cross-fades the label with a pre-blurred image of the same text.
final class GiftStatsNumericPiece: UIView {
    private static let padding: CGFloat = 12.0
    /// In points.
    private static let blurRadius: CGFloat = 3.0
    private static let images = NSCache<NSString, UIImage>()

    let text: String
    let content = UIView()
    let label = UILabel()
    private var blurView: UIImageView?

    init(text: String, font: UIFont, color: UIColor, width: CGFloat, height: CGFloat) {
        self.text = text
        super.init(frame: CGRect(x: 0.0, y: 0.0, width: width, height: height))
        self.isUserInteractionEnabled = false
        self.isAccessibilityElement = false
        self.accessibilityElementsHidden = true
        self.content.frame = self.bounds
        self.addSubview(self.content)
        // Extra width so fractional advances never truncate the text.
        self.label.frame = CGRect(x: 0.0, y: 0.0, width: width + 2.0, height: height)
        self.label.font = font
        self.label.textColor = color
        self.label.lineBreakMode = .byClipping
        self.label.text = text
        self.label.isAccessibilityElement = false
        self.content.addSubview(self.label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static var isWarmedUp = false

    /// Pre-renders blurred digits for the value tiles in the background. Call on the main thread.
    static func warmUp() {
        guard !self.isWarmedUp else {
            return
        }
        self.isWarmedUp = true
        let font = GiftStatsValueTileView.numberFont(size: 18.0)
        DispatchQueue.global(qos: .utility).async {
            for digit in 0 ... 9 {
                let text = String(digit)
                let size = CGSize(width: GiftStatsNumericPiece.advance(of: text, font: font), height: GiftStatsNumericTextView.lineHeight(of: font))
                _ = GiftStatsNumericPiece.blurredImage(text: text, font: font, color: .white, size: size)
            }
        }
    }

    static func advance(of text: String, font: UIFont) -> CGFloat {
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    func place(x: CGFloat) {
        self.center = CGPoint(x: x + self.bounds.width / 2.0, y: self.bounds.height / 2.0)
    }

    func blur(font: UIFont, color: UIColor) -> UIImageView {
        if let blurView = self.blurView {
            return blurView
        }
        let padding = GiftStatsNumericPiece.padding
        let view = UIImageView(frame: self.bounds.insetBy(dx: -padding, dy: -padding))
        view.image = GiftStatsNumericPiece.blurredImage(text: self.text, font: font, color: color, size: self.bounds.size)
        view.isUserInteractionEnabled = false
        self.content.addSubview(view)
        self.blurView = view
        return view
    }

    func dropBlur() {
        self.blurView?.removeFromSuperview()
        self.blurView = nil
    }

    private static func blurredImage(text: String, font: UIFont, color: UIColor, size: CGSize) -> UIImage? {
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let key = "\(text)|\(font.fontName)|\(font.pointSize)|\(red)|\(green)|\(blue)|\(alpha)" as NSString
        if let cached = self.images.object(forKey: key) {
            return cached
        }
        let padding = self.padding
        let imageSize = CGSize(width: size.width + padding * 2.0, height: size.height + padding * 2.0)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreenScale
        format.opaque = false
        let source = UIGraphicsImageRenderer(size: imageSize, format: format).image { _ in
            (text as NSString).draw(at: CGPoint(x: padding, y: padding), withAttributes: [.font: font, .foregroundColor: color])
        }
        guard let input = CIImage(image: source), let filter = CIFilter(name: "CIGaussianBlur") else {
            return source
        }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(self.blurRadius * UIScreenScale, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage, let cgImage = GiftStatsImageContext.shared.createCGImage(output, from: input.extent) else {
            return source
        }
        let image = UIImage(cgImage: cgImage, scale: UIScreenScale, orientation: .up)
        self.images.setObject(image, forKey: key)
        return image
    }
}
