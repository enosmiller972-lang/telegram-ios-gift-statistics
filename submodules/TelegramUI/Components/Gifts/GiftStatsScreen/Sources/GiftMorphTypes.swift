import Foundation
import UIKit

// frame is in card coordinates.
public struct GiftMorphLook {
    public var frame: CGRect
    public var radius: CGFloat
    public var flat: GiftFlat

    public init(frame: CGRect, radius: CGFloat, flat: GiftFlat) {
        self.frame = frame
        self.radius = radius
        self.flat = flat
    }
}

// Content clipped to a piece's surface: a snapshot or the real views.
public final class GiftMorphThing {
    public enum Path: Equatable {
        case rigid
        // Maps to the row with the same index at the other end.
        case row(Int)
        case trailing(inset: CGFloat)
    }

    public let view: UIView
    public let path: Path
    // In card coordinates.
    public let home: () -> CGRect
    // Move real views into view and back; no-ops for snapshots.
    public let activate: () -> Void
    public let release: () -> Void

    public init(view: UIView, path: Path = .rigid, home: @escaping () -> CGRect, activate: @escaping () -> Void = {}, release: @escaping () -> Void = {}) {
        self.view = view
        self.path = path
        self.home = home
        self.activate = activate
        self.release = release
    }

    public convenience init(picture: UIView, frame: CGRect, path: Path = .rigid) {
        self.init(view: picture, path: path, home: { frame })
    }

    func rigid() -> GiftMorphThing {
        return GiftMorphThing(view: self.view, path: .rigid, home: self.home, activate: self.activate, release: self.release)
    }
}

// Shadow or rim of the real target view, faded in over GiftMorphTiming.settle so the final swap is seamless.
public struct GiftMorphAccent {
    public var image: UIImage
    public var outset: CGFloat
    public var alpha: CGFloat
    public var compositingFilter: Any?
    public var isUnder: Bool

    public init(image: UIImage, outset: CGFloat, alpha: CGFloat, compositingFilter: Any?, isUnder: Bool) {
        self.image = image
        self.outset = outset
        self.alpha = alpha
        self.compositingFilter = compositingFilter
        self.isUnder = isUnder
    }
}

public final class GiftMorphEnd {
    public let reveal: [UIView]
    // False when the element has no surface of its own (e.g. the Value row); the piece's surface then fades.
    public let hasSurface: Bool
    public let hide: () -> Void
    public let revealing: () -> Void
    private let makeAccents: () -> [GiftMorphAccent]
    public private(set) var accents: [GiftMorphAccent] = []
    private let makeLook: () -> GiftMorphLook
    private let makeThings: (_ isFrozen: Bool) -> [GiftMorphThing]
    private var frozenLook: GiftMorphLook?
    public private(set) var things: [GiftMorphThing] = []
    public private(set) var isCaptured = false

    public init(
        reveal: [UIView],
        hasSurface: Bool = true,
        look: @escaping () -> GiftMorphLook,
        things: @escaping (_ isFrozen: Bool) -> [GiftMorphThing],
        hide: @escaping () -> Void,
        revealing: @escaping () -> Void = {},
        accents: @escaping () -> [GiftMorphAccent] = { [] }
    ) {
        self.makeAccents = accents
        self.reveal = reveal
        self.hasSurface = hasSurface
        self.makeLook = look
        self.makeThings = things
        self.hide = hide
        self.revealing = revealing
    }

    // isFrozen: the source end, whose geometry must be recorded before the card is relaid out.
    public func capture(isFrozen: Bool) {
        self.things = self.makeThings(isFrozen)
        self.accents = self.makeAccents()
        self.frozenLook = isFrozen ? self.makeLook() : nil
        self.isCaptured = true
    }

    public var look: GiftMorphLook {
        return self.frozenLook ?? self.makeLook()
    }
}

// When one end is missing, the surface grows out of (or melts into) near.
public struct GiftMorphPair {
    public var card: GiftMorphEnd?
    public var stats: GiftMorphEnd?
    public var near: GiftMorphEnd?
    // No card end: separates from the bottom edge of near.
    public var emerges: Bool
    // Unpaired blocks ride this pair's edges.
    public var isAnchor: Bool
    // Cross-dissolve the content instead of the reel push.
    public var dissolves: Bool
    // Shape follows its own ease (GiftMorphTiming.shrinkDone) instead of the card height.
    public var isQuick: Bool
    // Card surface with no visible counterpart grows out of the edge of near.
    public var isBorn: Bool
    // No card end: shrinks into the top edge of this panel instead of travelling to near.
    public var mergesInto: GiftMorphEnd?
    // No card end: fades out in place without travelling.
    public var fadesOut: Bool
    // Surfaceless card element that follows the bottom edge of this end's piece.
    public var ridesBelow: GiftMorphEnd?
    // Fill changes over window together with the content, not by the card position.
    public var fillsInWindow: Bool
    // Placed from the card's bottom edge, which stays still on screen. Measuring from the top would lag by the
    // height the card gains in the frame between reading and display.
    public var anchorsBottom: Bool
    public var window: GiftMorphWindow

    public init(card: GiftMorphEnd?, stats: GiftMorphEnd?, near: GiftMorphEnd? = nil, emerges: Bool = false, isAnchor: Bool = false, dissolves: Bool = false, isBorn: Bool = false, isQuick: Bool = false, mergesInto: GiftMorphEnd? = nil, fadesOut: Bool = false, ridesBelow: GiftMorphEnd? = nil, anchorsBottom: Bool = false, fillsInWindow: Bool = false, window: GiftMorphWindow = GiftMorphTiming.tiles) {
        self.ridesBelow = ridesBelow
        self.anchorsBottom = anchorsBottom
        self.fillsInWindow = fillsInWindow
        self.window = window
        self.card = card
        self.stats = stats
        self.near = near
        self.emerges = emerges
        self.isAnchor = isAnchor
        self.dissolves = dissolves
        self.isBorn = isBorn
        self.isQuick = isQuick
        self.mergesInto = mergesInto
        self.fadesOut = fadesOut
    }
}

struct GiftMorphBottom {
    var cardHeight: CGFloat
    var statsHeight: CGFloat
    var endHeight: CGFloat
}

// Unpaired stats content that rides an edge of a piece and fades over its window.
public struct GiftMorphBlock {
    public enum Ride {
        case top
        case bottom
        case still
    }

    public var views: [UIView]
    public var ride: Ride
    // nil: the anchor pair.
    public var panel: GiftMorphEnd?
    public var window: GiftMorphWindow

    public init(views: [UIView], ride: Ride, panel: GiftMorphEnd? = nil, window: GiftMorphWindow = GiftMorphTiming.blocks) {
        self.views = views
        self.ride = ride
        self.panel = panel
        self.window = window
    }
}
