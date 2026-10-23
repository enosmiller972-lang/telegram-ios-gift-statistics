import Foundation
import TelegramCore

/// Replaces server-provided series names and colours with localized names and the sheet's colours.
enum GiftStatsGraphNames {
    static func localized(_ graph: StatsGraph, names: [String: String], colors: [String: String] = [:]) -> StatsGraph {
        guard case let .Loaded(token, data) = graph, let jsonData = data.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any],
              var current = object["names"] as? [String: String] else {
            return graph
        }
        for (id, name) in names where current[id] != nil {
            current[id] = name
        }
        object["names"] = current
        if var currentColors = object["colors"] as? [String: String] {
            for (id, color) in colors where currentColors[id] != nil {
                currentColors[id] = color
            }
            object["colors"] = currentColors
        }
        guard let result = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), let text = String(data: result, encoding: .utf8) else {
            return graph
        }
        return .Loaded(token: token, data: text)
    }
}
