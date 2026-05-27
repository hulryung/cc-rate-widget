import XCTest

final class LimitInferrerTests: XCTestCase {
    func test_emptyHistory_returnsLearningState() {
        var limits = InferredLimits(weeklyMaxObserved: 0, fiveHourMaxObserved: 0)
        let result = LimitInferrer.infer(currentSnapshot: snap(),
                                         weeklySamples: [],
                                         fiveHourSamples: [],
                                         limits: &limits)
        XCTAssertNil(result.fiveHourTokens)
        XCTAssertNil(result.sevenDayTokens)
    }

    func test_weeklyMaxObserved_drivesRatchet() {
        var limits = InferredLimits(weeklyMaxObserved: 1_000_000, fiveHourMaxObserved: 100_000)
        let result = LimitInferrer.infer(currentSnapshot: snap(fiveH: 50_000, sevenD: 600_000),
                                         weeklySamples: [],
                                         fiveHourSamples: [],
                                         limits: &limits)
        // max(1_000_000 * 1.05, P90([]) * 1.2) → 1_050_000
        XCTAssertEqual(result.sevenDayTokens, 1_050_000)
    }

    func test_manualOverride_beatsP90() {
        var limits = InferredLimits(weeklyMaxObserved: 1_000_000,
                                    fiveHourMaxObserved: 100_000,
                                    manualPlanTier: .max20)
        let result = LimitInferrer.infer(currentSnapshot: snap(),
                                         weeklySamples: [10, 20, 30],
                                         fiveHourSamples: [],
                                         limits: &limits)
        XCTAssertEqual(result.sevenDayTokens, LimitInferrer.standardLimits[.max20]!.sevenDay)
    }

    func test_officialOAuth_beatsManualAndP90() {
        var limits = InferredLimits(weeklyMaxObserved: 1_000_000,
                                    fiveHourMaxObserved: 100_000,
                                    officialFiveHourTokens: 12345,
                                    officialSevenDayTokens: 67890,
                                    manualPlanTier: .max20)
        let result = LimitInferrer.infer(currentSnapshot: snap(),
                                         weeklySamples: [],
                                         fiveHourSamples: [],
                                         limits: &limits)
        XCTAssertEqual(result.fiveHourTokens, 12345)
        XCTAssertEqual(result.sevenDayTokens, 67890)
    }

    func test_currentSnapshot_above_weeklyMaxObserved_updatesObserved() {
        var limits = InferredLimits(weeklyMaxObserved: 1_000_000, fiveHourMaxObserved: 100_000)
        _ = LimitInferrer.infer(currentSnapshot: snap(fiveH: 0, sevenD: 1_500_000),
                                weeklySamples: [],
                                fiveHourSamples: [],
                                limits: &limits)
        XCTAssertEqual(limits.weeklyMaxObserved, 1_500_000)
    }

    private func snap(fiveH: Int = 0, sevenD: Int = 0) -> AggregationSnapshot {
        AggregationSnapshot(
            fiveHourTokens: fiveH, sevenDayTokens: sevenD, sevenDaySonnetTokens: 0,
            fiveHourCost: 0, sevenDayCost: 0,
            earliestInFiveHour: nil, earliestInSevenDay: nil,
            projects: ProjectBreakdown(entries: []),
            lastHalfHourTokensPerSecond: 0
        )
    }
}
