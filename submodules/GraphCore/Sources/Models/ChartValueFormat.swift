import Foundation
#if os(macOS)
import Cocoa
#else
import UIKit
#endif

/// Display format for axis and popup values: value / `divisor` after `prefix`, e.g. cents shown as "$4,180".
public struct ChartValueFormat {
    public var divisor: Double
    public var prefix: String
    public var groupingSeparator: String
    public var decimalSeparator: String

    public init(divisor: Double, prefix: String, groupingSeparator: String, decimalSeparator: String) {
        self.divisor = divisor
        self.prefix = prefix
        self.groupingSeparator = groupingSeparator
        self.decimalSeparator = decimalSeparator
    }

    public func string(from value: Double) -> String {
        let scaled = value / self.divisor
        // Compact form ("12.3K") keeps axis labels within the reserved gutter.
        if abs(scaled) >= 10_000.0 {
            return self.compactString(from: scaled)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = self.groupingSeparator
        formatter.decimalSeparator = self.decimalSeparator
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = abs(scaled) < 100.0 && scaled.rounded() != scaled ? 2 : 0
        return self.prefix + (formatter.string(from: NSNumber(value: scaled)) ?? "")
    }

    private func compactString(from scaled: Double) -> String {
        let magnitude = abs(scaled)
        let units: [(Double, String)] = [(1_000_000_000.0, "B"), (1_000_000.0, "M"), (1_000.0, "K")]
        var text = String(format: "%.0f", magnitude)
        for (size, suffix) in units where magnitude >= size {
            let shortened = (magnitude / size * 10.0).rounded() / 10.0
            var number = String(format: "%.1f", shortened)
            if number.hasSuffix(".0") {
                number.removeLast(2)
            } else {
                number = number.replacingOccurrences(of: ".", with: self.decimalSeparator)
            }
            text = number + suffix
            break
        }
        return (scaled < 0.0 ? "-" : "") + self.prefix + text
    }

    public func string(from value: CGFloat) -> String {
        return self.string(from: Double(value))
    }
}
