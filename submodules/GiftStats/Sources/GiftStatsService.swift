import Foundation

/// Provider used by the gift screens; statistics stay hidden until one is set.
public final class GiftStatsService {
    public static let shared = GiftStatsService()

    private let lock = NSLock()
    private var currentProvider: GiftStatsProvider = UnavailableGiftStatsProvider()

    /// Can be replaced from any thread.
    public var provider: GiftStatsProvider {
        get {
            self.lock.lock()
            defer {
                self.lock.unlock()
            }
            return self.currentProvider
        }
        set {
            self.lock.lock()
            self.currentProvider = newValue
            self.lock.unlock()
        }
    }

    private init() {
    }
}
