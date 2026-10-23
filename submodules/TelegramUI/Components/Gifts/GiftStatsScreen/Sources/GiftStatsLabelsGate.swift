import Foundation
import UIKit

/// Hides one card's chart date labels during the morph, where they would show through the glass. One gate per card.
final class GiftStatsLabelsGate {
    private let charts = NSHashTable<GiftStatsChartComponent.View>.weakObjects()

    var isHidden = false {
        didSet {
            if oldValue != self.isHidden {
                for chart in self.charts.allObjects {
                    chart.applyLabelsHidden(animated: true)
                }
            }
        }
    }

    func add(_ chart: GiftStatsChartComponent.View) {
        self.charts.add(chart)
    }
}
