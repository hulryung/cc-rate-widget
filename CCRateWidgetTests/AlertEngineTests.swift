import XCTest

final class AlertEngineTests: XCTestCase {
    func test_eightyCrossing_emitsAlert() {
        let prev = state(util: 0.79)
        let new  = state(util: 0.81)
        let alerts = AlertEngine.evaluate(prev: prev, new: new, now: Date())
        XCTAssertEqual(alerts.first?.kind, .threshold(0.80))
    }

    func test_eightyCrossing_doesNotRepeatSameWindow() {
        let prev = state(util: 0.81, lastThresholdFired: 0.80)
        let new  = state(util: 0.82, lastThresholdFired: 0.80)
        let alerts = AlertEngine.evaluate(prev: prev, new: new, now: Date())
        XCTAssertTrue(alerts.isEmpty)
    }

    func test_windowResetRearmsThreshold() {
        let resetTime = Date().addingTimeInterval(-60)
        let prev = state(util: 0.82, lastThresholdFired: 0.80, resetsAt: resetTime)
        let new  = state(util: 0.81, lastThresholdFired: nil,  resetsAt: resetTime.addingTimeInterval(3600))
        let alerts = AlertEngine.evaluate(prev: prev, new: new, now: Date())
        XCTAssertEqual(alerts.first?.kind, .threshold(0.80))
    }

    func test_forecast_etaUnderRemainingMinus30_emits() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(2 * 3600)
        let new = state(util: 0.50, resetsAt: resetsAt, burnTokensPerSec: 100, inferredLimit: 1_000_000)
        let alerts = AlertEngine.evaluate(prev: state(util: 0.50, resetsAt: resetsAt),
                                          new: new, now: now)
        XCTAssertTrue(alerts.contains { if case .forecast = $0.kind { return true } else { return false } })
    }

    func test_forecast_zeroBurn_doesNotEmit() {
        let now = Date()
        let new = state(util: 0.50, resetsAt: now.addingTimeInterval(3600),
                        burnTokensPerSec: 0, inferredLimit: 1_000_000)
        let alerts = AlertEngine.evaluate(prev: new, new: new, now: now)
        XCTAssertFalse(alerts.contains { if case .forecast = $0.kind { return true } else { return false } })
    }

    private func state(util: Double,
                       lastThresholdFired: Double? = nil,
                       resetsAt: Date? = nil,
                       burnTokensPerSec: Double = 0,
                       inferredLimit: Int = 1_000_000) -> AlertEngine.State {
        .init(
            utilization: util,
            resetsAt: resetsAt,
            lastThresholdFired: lastThresholdFired,
            forecastFiredAt: nil,
            burnTokensPerSec: burnTokensPerSec,
            inferredLimitTokens: inferredLimit,
            currentTokens: Int(Double(inferredLimit) * util)
        )
    }
}
