import Foundation
import TelegramCore

public extension StarGift.UniqueGift {
    /// Scope of the gifts sharing this gift's model; nil for a gift without a model.
    var modelStatsScope: GiftStatsScope? {
        for attribute in self.attributes {
            if case let .model(_, file, _, _) = attribute {
                return .model(fileId: file.fileId.id)
            }
        }
        return nil
    }
}

public extension Int64 {
    init(saturating value: Double) {
        if value.isNaN {
            self = 0
        } else if value >= 9_223_372_036_854_775_807.0 {
            self = Int64.max
        } else if value <= -9_223_372_036_854_775_808.0 {
            self = Int64.min
        } else {
            self = Int64(value)
        }
    }
}

public extension Int32 {
    init(saturating value: Double) {
        if value.isNaN {
            self = 0
        } else if value >= Double(Int32.max) {
            self = Int32.max
        } else if value <= Double(Int32.min) {
            self = Int32.min
        } else {
            self = Int32(value)
        }
    }
}
