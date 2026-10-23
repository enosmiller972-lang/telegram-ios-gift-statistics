import Foundation
import UIKit
import TelegramPresentationData
import TelegramStringFormatting

public enum GiftStatsFormat {
    /// US cents. "$4,181" (rounded to the dollar) from $100 up, "$41.80" below.
    public static func price(_ cents: Int64, dateTimeFormat: PresentationDateTimeFormat) -> String {
        let negative = cents < 0
        let amount = abs(cents)
        var text: String
        if amount >= 10000 {
            let dollars = amount / 100 + (amount % 100 >= 50 ? 1 : 0)
            text = "$" + presentationStringsFormattedNumber(dollars, dateTimeFormat.groupingSeparator)
        } else {
            let fraction = amount % 100
            text = "$\(amount / 100)\(dateTimeFormat.decimalSeparator)\(fraction < 10 ? "0" : "")\(fraction)"
        }
        return negative ? "-" + text : text
    }

    private static let minute: Int32 = 60
    private static let hour: Int32 = 3600
    private static let day: Int32 = 86400
    private static let week: Int32 = 7 * 86400
    private static let month: Int32 = 30 * 86400
    private static let year: Int32 = 365 * 86400

    /// "5m ago", "2h ago", "3d ago", "2w ago", "3mo ago", "1y ago".
    public static func ago(date: Int32, now: Int32, strings: PresentationStrings) -> String {
        let seconds = max(0, now - date)
        if seconds < minute {
            return strings.Gift_Stats_AgoNow
        } else if seconds < hour {
            return strings.Gift_Stats_AgoMinutes("\(seconds / minute)").string
        } else if seconds < day {
            return strings.Gift_Stats_AgoHours("\(seconds / hour)").string
        } else if seconds < week {
            return strings.Gift_Stats_AgoDays("\(seconds / day)").string
        } else if seconds < month {
            return strings.Gift_Stats_AgoWeeks("\(seconds / week)").string
        } else if seconds < year {
            return strings.Gift_Stats_AgoMonths("\(seconds / month)").string
        }
        return strings.Gift_Stats_AgoYears("\(seconds / year)").string
    }

    /// VoiceOver variant with the unit spelled out: "5 hours ago".
    public static func spokenAgo(date: Int32, now: Int32, strings: PresentationStrings) -> String {
        let seconds = max(0, now - date)
        if seconds < minute {
            return strings.Gift_Stats_AgoNow
        }
        return strings.Gift_Stats_AgoSpoken(timeIntervalString(strings: strings, value: seconds)).string
    }

    public static func join(_ first: String, _ second: String, strings: PresentationStrings) -> String {
        return strings.Gift_Stats_Join(first, second).string
    }

    public static func join(_ parts: [String], strings: PresentationStrings) -> String {
        var result = ""
        for part in parts where !part.isEmpty {
            result = result.isEmpty ? part : self.join(result, part, strings: strings)
        }
        return result
    }

    /// `attributes` apply to the separator only.
    public static func join(_ first: NSAttributedString, _ second: NSAttributedString, attributes: [NSAttributedString.Key: Any], strings: PresentationStrings) -> NSAttributedString {
        let formatted = strings.Gift_Stats_Separator("1", "2")
        let result = NSMutableAttributedString(string: formatted.string, attributes: attributes)
        for item in formatted.ranges.sorted(by: { $0.range.location > $1.range.location }) where item.range.location != NSNotFound && NSMaxRange(item.range) <= result.length {
            result.replaceCharacters(in: item.range, with: item.index == 0 ? first : second)
        }
        return result
    }
}
