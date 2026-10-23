import Foundation
import UIKit

/// Spring dynamics solver stepped by display link.
struct GiftStatsSpring {
    var value: CGFloat
    var target: CGFloat
    var velocity: CGFloat = 0.0
    var stiffness: CGFloat = 520.0
    var damping: CGFloat = 36.0

    init(_ value: CGFloat) {
        self.value = value
        self.target = value
    }

    var isResting: Bool {
        return abs(self.value - self.target) < 0.05 && abs(self.velocity) < 0.5
    }

    mutating func step(_ dt: CGFloat) {
        // Semi-implicit Euler in small steps, so a long frame does not blow the spring up.
        var remaining = min(dt, 0.05)
        while remaining > 0.0 {
            let h = min(remaining, 1.0 / 240.0)
            let force = (self.target - self.value) * self.stiffness - self.velocity * self.damping
            self.velocity += force * h
            self.value += self.velocity * h
            remaining -= h
        }
        if self.isResting {
            self.value = self.target
            self.velocity = 0.0
        }
    }
}
