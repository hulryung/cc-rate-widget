import XCTest

final class PricingTests: XCTestCase {
    func test_opus47_cost_perMillion() {
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0)
        let cost = Pricing.cost(model: "claude-opus-4-7", usage: usage)
        // 15 + 75 = 90
        XCTAssertEqual(cost, 90.0, accuracy: 0.0001)
    }

    func test_sonnet46_cost_includesCacheWrite() {
        let usage = TokenUsage(input: 0, output: 0, cacheWrite: 1_000_000, cacheRead: 0)
        let cost = Pricing.cost(model: "claude-sonnet-4-6", usage: usage)
        XCTAssertEqual(cost, 3.75, accuracy: 0.0001)
    }

    func test_unknownModel_cost_isZero() {
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0)
        let cost = Pricing.cost(model: "claude-mystery-9-0", usage: usage)
        XCTAssertEqual(cost, 0)
    }

    func test_tokenSum_excludesCacheRead() {
        let usage = TokenUsage(input: 100, output: 50, cacheWrite: 25, cacheRead: 99999)
        XCTAssertEqual(usage.utilizationTokens, 175)
    }
}
