import Foundation

enum LimitInferrer {
    struct StandardLimits {
        let fiveHour: Int
        let sevenDay: Int
    }

    /// Educated guesses for the standard plan tiers. Easy to bump as Anthropic publishes numbers.
    static let standardLimits: [InferredLimits.ManualPlanTier: StandardLimits] = [
        .pro:   StandardLimits(fiveHour:   200_000, sevenDay:   2_000_000),
        .max5:  StandardLimits(fiveHour: 1_000_000, sevenDay:  10_000_000),
        .max20: StandardLimits(fiveHour: 4_000_000, sevenDay:  40_000_000),
    ]

    struct Result {
        let fiveHourTokens: Int?
        let sevenDayTokens: Int?
        let sevenDaySonnetTokens: Int?
    }

    static func infer(
        currentSnapshot: AggregationSnapshot,
        weeklySamples: [Int],
        fiveHourSamples: [Int],
        limits: inout InferredLimits
    ) -> Result {
        // Ratchet observed maxes.
        if currentSnapshot.sevenDayTokens > limits.weeklyMaxObserved {
            limits.weeklyMaxObserved = currentSnapshot.sevenDayTokens
        }
        if currentSnapshot.fiveHourTokens > limits.fiveHourMaxObserved {
            limits.fiveHourMaxObserved = currentSnapshot.fiveHourTokens
        }

        // 1) Cached official from OAuth wins.
        if let f = limits.officialFiveHourTokens, let s = limits.officialSevenDayTokens {
            return Result(fiveHourTokens: f, sevenDayTokens: s, sevenDaySonnetTokens: s)
        }

        // 2) Manual override.
        if let tier = limits.manualPlanTier, let std = standardLimits[tier] {
            return Result(
                fiveHourTokens: std.fiveHour,
                sevenDayTokens: std.sevenDay,
                sevenDaySonnetTokens: std.sevenDay
            )
        }

        // 3) P90 + ratchet. Returns nil if we have neither observed-max nor samples (learning).
        let inferred5h = inferOne(samples: fiveHourSamples, observedMax: limits.fiveHourMaxObserved)
        let inferred7d = inferOne(samples: weeklySamples,   observedMax: limits.weeklyMaxObserved)

        return Result(
            fiveHourTokens: inferred5h,
            sevenDayTokens: inferred7d,
            sevenDaySonnetTokens: inferred7d
        )
    }

    private static func inferOne(samples: [Int], observedMax: Int) -> Int? {
        let ratchet = observedMax > 0 ? Int(Double(observedMax) * 1.05) : nil
        let p90 = percentile(samples, p: 0.90).map { Int(Double($0) * 1.2) }
        switch (ratchet, p90) {
        case let (.some(r), .some(p)): return max(r, p)
        case let (.some(r), .none):    return r
        case let (.none, .some(p)):    return p
        case (.none, .none):           return nil
        }
    }

    private static func percentile(_ samples: [Int], p: Double) -> Int? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let idx = max(0, min(sorted.count - 1, Int(Double(sorted.count - 1) * p)))
        return sorted[idx]
    }
}
