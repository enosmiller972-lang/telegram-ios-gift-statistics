import Foundation
import UIKit
import GiftStats

// Progress comes from the card's height animation (0 card, 1 stats). The presentation height lags by a frame,
// so it is only used where the ease is steep to correct the estimated start time; each frame then evaluates
// the ease at its display time. Falls back to plain time when the heights barely differ.
final class GiftMorphClock {
    private static let minimumChange: CGFloat = 6.0
    private static let tolerance: CGFloat = 0.05
    private static let nearEnd: CGFloat = 0.4
    private static let minimumDuration: Double = 0.25
    // Delay between the display link tick and the main thread commit.
    static let commitDelay: Double = 0.0015
    private static let steepFrom: CGFloat = 0.12
    private static let steepTo: CGFloat = 0.88
    // Start-time correction gain and per-frame clamp.
    private static let gain: Double = 0.25
    private static let reach: Double = 0.03
    // Initial guess of the card animation start relative to the link start, measured on the simulator.
    private static let firstStartToStats: Double = 0.02
    private static let firstStartBack: Double = -0.023

    private let host: UIView
    private let startHeight: CGFloat
    private let toStats: Bool
    private let duration: Double
    private(set) var moment: GiftMorphMoment
    private(set) var isSettled = false
    private var start: Double?
    private var previousTick: Double?

    init(host: UIView, startHeight: CGFloat, toStats: Bool) {
        self.host = host
        self.startHeight = startHeight
        self.toStats = toStats
        self.duration = GiftMorphTiming.duration * Double(max(1.0, UIView.animationDurationFactor))
        let position: CGFloat = toStats ? 0.0 : 1.0
        self.moment = GiftMorphMoment(position: position, time: position)
    }

    // Call once per frame; displayTime is when this frame reaches the screen.
    func step(elapsed: Double, now: Double, displayTime: Double) -> GiftMorphMoment {
        let endHeight = self.host.bounds.height
        let change = abs(endHeight - self.startHeight)
        var isArrived: Bool
        if change >= GiftMorphClock.minimumChange {
            let read = self.host.layer.presentation()?.bounds.height ?? endHeight
            let cardHeight = self.toStats ? self.startHeight : endHeight
            let statsHeight = self.toStats ? endHeight : self.startHeight
            let reading = min(1.0, max(0.0, (read - cardHeight) / (statsHeight - cardHeight)))
            let progress = self.toStats ? reading : 1.0 - reading
            let interval = now - (self.previousTick ?? now - elapsed)
            self.previousTick = now
            var start = self.start ?? (now - elapsed) + (self.toStats ? GiftMorphClock.firstStartToStats : GiftMorphClock.firstStartBack)
            if progress > GiftMorphClock.steepFrom && progress < GiftMorphClock.steepTo {
                let share = Double(GiftMorphTiming.time(atProgress: progress))
                let said = (now - interval + GiftMorphClock.commitDelay) - share * self.duration
                start += GiftMorphClock.gain * min(GiftMorphClock.reach, max(-GiftMorphClock.reach, said - start))
            }
            self.start = start
            let share = CGFloat(min(1.0, max(0.0, (displayTime - start) / self.duration)))
            let eased = GiftMorphTiming.progress(atTime: share)
            self.moment = GiftMorphMoment(position: self.toStats ? eased : 1.0 - eased, time: self.toStats ? share : 1.0 - share)
            isArrived = abs(read - endHeight) < GiftMorphClock.tolerance || (share >= 1.0 && abs(read - endHeight) < GiftMorphClock.nearEnd)
        } else {
            let run = CGFloat(min(1.0, max(0.0, elapsed / GiftMorphTiming.duration)))
            let time = self.toStats ? run : 1.0 - run
            self.moment = GiftMorphMoment(position: GiftMorphTiming.progress(atTime: time), time: time)
            isArrived = elapsed >= GiftMorphTiming.duration
        }
        if elapsed < GiftMorphClock.minimumDuration {
            isArrived = false
        }
        self.isSettled = isArrived
        return self.moment
    }
}
