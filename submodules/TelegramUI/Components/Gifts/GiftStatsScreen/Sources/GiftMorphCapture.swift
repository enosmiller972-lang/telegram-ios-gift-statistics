import Foundation
import UIKit
import Display

public enum GiftMorphCapture {
    // Hidden views render empty, so temporarily show the ones waiting to fade in.
    public static func withShown<T>(_ views: [UIView], _ body: () -> T) -> T {
        let saved = views.map { $0.alpha }
        for view in views {
            view.alpha = 1.0
        }
        let result = body()
        for (view, alpha) in zip(views, saved) {
            view.alpha = alpha
        }
        return result
    }

    // Shown on screen: in a window, and neither it nor any ancestor hidden or transparent.
    public static func isOnScreen(_ view: UIView) -> Bool {
        guard view.window != nil else {
            return false
        }
        var current: UIView? = view
        while let item = current {
            if item.isHidden || item.alpha < 0.01 || item.layer.opacity < 0.01 {
                return false
            }
            current = item.superview
        }
        return true
    }

    // layer.render instead of afterScreenUpdates snapshots, which would commit and flash views shown by withShown.
    public static func picture(of view: UIView, rect: CGRect? = nil) -> UIView? {
        let area = rect ?? view.bounds
        guard let image = self.image(size: area.size, draw: { context in
            context.translateBy(x: -area.minX, y: -area.minY)
            view.layer.render(in: context)
        }) else {
            return nil
        }
        let picture = UIImageView(image: image)
        picture.frame = CGRect(origin: .zero, size: area.size)
        return picture
    }

    // Exactly the pixels of the frame, rounded. Left to the renderer, a height like 39.666…7 pt gets a pixel row more
    // (119.000…1 rounded up); squeezed back into its frame, the picture then sits half a pixel off the real view
    // and steps into place when the real view takes over.
    private static func image(size: CGSize, draw: (CGContext) -> Void) -> UIImage? {
        let scale = UIScreenScale
        let pixels = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        guard pixels.width > 0.0, pixels.height > 0.0 else {
            return nil
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: pixels, format: format).image { context in
            context.cgContext.scaleBy(x: scale, y: scale)
            // A scaled-down image (an avatar of 180 px in 66) the way the screen draws it (the layer's linear filter);
            // the default smoother filter would make it softer in the morph than after it.
            context.cgContext.interpolationQuality = .low
            draw(context.cgContext)
        }
        return image.cgImage.map { UIImage(cgImage: $0, scale: scale, orientation: .up) }
    }

    public static func thing(_ picture: UIView, standingFor view: UIView, in card: UIView, isFrozen: Bool) -> GiftMorphThing {
        let frame = view.convert(view.bounds, to: card)
        if isFrozen {
            return GiftMorphThing(picture: picture, frame: frame)
        }
        return GiftMorphThing(view: picture, home: { [weak view, weak card] in
            guard let view, let card else {
                return frame
            }
            return view.convert(view.bounds, to: card)
        })
    }

    // Subviews only, without the fill and rim.
    public static func picture(onFlat flat: GiftFlatTonalView, in card: UIView, isFrozen: Bool) -> GiftMorphThing? {
        let area = flat.bounds
        guard let image = self.image(size: area.size, draw: { context in
            for subview in flat.subviews where !subview.isHidden && subview.alpha > 0.0 && !(subview is GiftRimView) {
                context.saveGState()
                context.translateBy(x: subview.frame.minX, y: subview.frame.minY)
                subview.layer.render(in: context)
                context.restoreGState()
            }
        }) else {
            return nil
        }
        let picture = UIImageView(image: image)
        picture.frame = CGRect(origin: .zero, size: area.size)
        let frame = flat.convert(area, to: card)
        if isFrozen {
            return GiftMorphThing(picture: picture, frame: frame)
        }
        return GiftMorphThing(view: picture, home: { [weak flat, weak card] in
            guard let flat, let card else {
                return frame
            }
            return flat.convert(flat.bounds, to: card)
        })
    }

    // Finds TableComponent row separators by shape (<= 1 pt high, full width minus GiftTonalPalette.inset).
    public static func rowBands(of table: UIView) -> [CGRect] {
        let width = table.bounds.width
        let lines = table.subviews.filter { view in
            return view.bounds.height <= 1.1 && view.bounds.width <= width + 1.0 && view.bounds.width >= width - GiftTonalPalette.inset * 2.0 - 1.0
        }.map { $0.frame.minY }.sorted()
        var bands: [CGRect] = []
        var top: CGFloat = 0.0
        for line in lines + [table.bounds.height] {
            if line - top > 1.5 {
                bands.append(CGRect(x: 0.0, y: top, width: width, height: line - top))
            }
            top = line
        }
        return bands
    }

    public static func rowViews(of table: UIView) -> [[UIView]] {
        let bands = self.rowBands(of: table)
        var rows = Array(repeating: [UIView](), count: bands.count)
        for view in table.subviews where !bands.isEmpty {
            let index = bands.firstIndex(where: { $0.maxY > view.frame.midY }) ?? bands.count - 1
            rows[index].append(view)
        }
        return rows.filter { !$0.isEmpty }
    }

    public static func allFlat(in view: UIView) -> [GiftFlatTonalView] {
        if let flat = view as? GiftFlatTonalView {
            return [flat]
        }
        return view.subviews.flatMap { self.allFlat(in: $0) }
    }

    // Running component animations would otherwise show up as duplicates next to the morph pieces.
    public static func removeAnimations(in view: UIView) {
        view.layer.removeAllAnimations()
        for subview in view.subviews {
            self.removeAnimations(in: subview)
        }
    }

    public static func rows(of table: UIView, in card: UIView, skipping skipped: CGRect?, isFrozen: Bool) -> [GiftMorphThing] {
        var things: [GiftMorphThing] = []
        var number = 0
        for band in self.rowBands(of: table) {
            if let skipped, abs(band.midY - skipped.midY) < band.height / 2.0 {
                continue
            }
            guard let picture = self.picture(of: table, rect: band) else {
                continue
            }
            let frame = table.convert(band, to: card)
            let path = GiftMorphThing.Path.row(number)
            number += 1
            let thing: GiftMorphThing
            if isFrozen {
                thing = GiftMorphThing(picture: picture, frame: frame, path: path)
            } else {
                thing = GiftMorphThing(view: picture, path: path, home: { [weak table, weak card] in
                    guard let table, let card else {
                        return frame
                    }
                    return table.convert(band, to: card)
                })
            }
            things.append(thing)
        }
        return things
    }
}
