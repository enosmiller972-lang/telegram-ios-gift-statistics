import Foundation

/// Deterministic so that preview statistics look the same on every run.
struct GiftStatsGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    /// FNV-1a; `String.hashValue` is randomized per launch.
    static func seed(for text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    // splitmix64
    mutating func next() -> UInt64 {
        self.state = self.state &+ 0x9e3779b97f4a7c15
        var z = self.state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double {
        return Double(self.next() >> 11) / Double(1 << 53)
    }

    /// In -1...1, biased to 0.
    mutating func centered() -> Double {
        return (self.unit() + self.unit() + self.unit()) / 1.5 - 1.0
    }
}

struct GiftStatsShape {
    static let dayCount = 365

    var floor: [Double]
    var sales: [Double]

    /// `lastFloor` is in US cents and is always the last value; `volume` is average sales per day.
    init(seed: UInt64, lastFloor: Double, volume: Double) {
        var generator = GiftStatsGenerator(seed: seed)
        let count = GiftStatsShape.dayCount

        // Mean-reverting log-price walk with a slowly changing drift.
        var logPrice = 0.0
        var drift = generator.centered() * 0.004
        var walk: [Double] = []
        for _ in 0 ..< count {
            drift = drift * 0.96 + generator.centered() * 0.0035
            logPrice = logPrice * 0.994 + drift + generator.centered() * 0.012
            walk.append(logPrice)
        }
        let scale = lastFloor / exp(walk[count - 1])
        self.floor = walk.map { max(1.0, exp($0) * scale).rounded() }

        // Weekly rhythm, a slow swell and a few spikes.
        var spikes: [Int: Double] = [:]
        for _ in 0 ..< 4 {
            spikes[Int(generator.unit() * Double(count - 20)) + 10] = 2.0 + generator.unit() * 2.5
        }
        let weekly: [Double] = [0.82, 0.86, 0.92, 0.98, 1.12, 1.26, 1.04]
        var sales: [Double] = []
        for index in 0 ..< count {
            var level = volume * weekly[index % 7] * (0.85 + 0.3 * sin(Double(index) / 58.0 + Double(seed % 7)))
            if let spike = spikes[index] {
                level *= spike
            }
            if spikes[index - 1] != nil {
                level *= 0.8
            }
            sales.append(GiftStatsShape.dailyCount(mean: level, generator: &generator))
        }
        self.sales = sales
    }

    /// Poisson-distributed count, so low-volume days vary instead of always rounding to the mean.
    private static func dailyCount(mean: Double, generator: inout GiftStatsGenerator) -> Double {
        if mean >= 30.0 {
            return max(0.0, (mean + mean.squareRoot() * generator.centered() * 1.7).rounded())
        }
        // Knuth's Poisson sampling.
        let limit = exp(-mean)
        var product = generator.unit()
        var count = 0.0
        while product > limit && count < 200.0 {
            product *= generator.unit()
            count += 1.0
        }
        return count
    }
}
