import Foundation
import UIKit

/// Viewer's own gift data for the "Your Item" section.
public struct GiftStatsYourItem: Equatable {
    public let usdCents: Int64
    public let isListed: Bool

    public init(usdCents: Int64, isListed: Bool) {
        self.usdCents = usdCents
        self.isListed = isListed
    }
}

/// Helper for pluralizing collection names.
enum GiftStatsCollectionName {
    static func plural(_ name: String, languageCode: String) -> String {
        guard languageCode == "en" else {
            return name
        }
        let lower = name.lowercased()
        guard let last = lower.last, last.isLetter else {
            return name
        }
        if lower.hasSuffix("ss") || lower.hasSuffix("x") || lower.hasSuffix("z") || lower.hasSuffix("ch") || lower.hasSuffix("sh") {
            return name + "es"
        }
        if last == "s" {
            return name
        }
        if last == "y", lower.count >= 2, !"aeiou".contains(lower[lower.index(lower.endIndex, offsetBy: -2)]) {
            return String(name.dropLast()) + "ies"
        }
        return name + "s"
    }

    /// Common prefix between singular and plural forms.
    static func stem(of name: String, plural: String) -> String {
        return String(zip(name, plural).prefix(while: { $0 == $1 }).map { $0.0 })
    }
}
