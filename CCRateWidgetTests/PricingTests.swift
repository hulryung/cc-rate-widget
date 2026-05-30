import XCTest

final class PricingTests: XCTestCase {
    func test_opus_cost_perMillion() {
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0)
        // Opus 4.5+ pricing: input $5 + output $25 = $30 per (1M in + 1M out).
        XCTAssertEqual(Pricing.cost(model: "claude-opus-4-7", usage: usage), 30.0, accuracy: 0.0001)
        XCTAssertEqual(Pricing.cost(model: "claude-opus-4-8", usage: usage), 30.0, accuracy: 0.0001)
    }

    func test_opus_cacheRead_isCheap() {
        let usage = TokenUsage(input: 0, output: 0, cacheWrite: 0, cacheRead: 1_000_000)
        // cache read $0.50/M — verified against ccusage.
        XCTAssertEqual(Pricing.cost(model: "claude-opus-4-8", usage: usage), 0.50, accuracy: 0.0001)
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
