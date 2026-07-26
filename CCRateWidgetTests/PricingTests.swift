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
        let cost = Pricing.cost(model: "gpt-4o", usage: usage)
        XCTAssertEqual(cost, 0)
    }

    // MARK: - Claude 5 generation

    /// These four are the models actually present in current Claude Code logs. Every one
    /// of them priced at $0 before the rate table was extended.
    func test_claude5_models_arePriced() {
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0)
        XCTAssertEqual(Pricing.cost(model: "claude-fable-5", usage: usage), 60.0, accuracy: 0.0001)
        XCTAssertEqual(Pricing.cost(model: "claude-opus-5", usage: usage), 30.0, accuracy: 0.0001)
        XCTAssertEqual(Pricing.cost(model: "claude-sonnet-5", usage: usage), 18.0, accuracy: 0.0001)
        XCTAssertEqual(Pricing.cost(model: "claude-opus-4-8", usage: usage), 30.0, accuracy: 0.0001)
    }

    /// Claude Code writes a bare shorthand when the user configures one.
    func test_bareModelAliases_arePriced() {
        let usage = TokenUsage(input: 1_000_000, output: 0, cacheWrite: 0, cacheRead: 0)
        XCTAssertEqual(Pricing.cost(model: "sonnet", usage: usage), 3.0, accuracy: 0.0001)
        XCTAssertEqual(Pricing.cost(model: "opus", usage: usage), 5.0, accuracy: 0.0001)
        XCTAssertEqual(Pricing.cost(model: "haiku", usage: usage), 1.0, accuracy: 0.0001)
    }

    /// The regression that caused this bug: a model newer than the table must fall back
    /// to its family's rate rather than silently costing nothing.
    func test_unrecognizedVersion_fallsBackToFamilyRate() {
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0)
        XCTAssertEqual(Pricing.cost(model: "claude-opus-9", usage: usage), 30.0, accuracy: 0.0001)
        XCTAssertEqual(Pricing.cost(model: "claude-sonnet-9", usage: usage), 18.0, accuracy: 0.0001)
        XCTAssertEqual(Pricing.cost(model: "claude-haiku-9", usage: usage), 6.0, accuracy: 0.0001)
        XCTAssertEqual(Pricing.cost(model: "claude-fable-9", usage: usage), 60.0, accuracy: 0.0001)
    }

    /// `<synthetic>` marks Claude Code's locally-generated messages. They carry zero
    /// usage, so they must contribute nothing rather than being force-priced.
    func test_syntheticModel_costsNothing() {
        let usage = TokenUsage(input: 0, output: 0, cacheWrite: 0, cacheRead: 0)
        XCTAssertEqual(Pricing.cost(model: "<synthetic>", usage: usage), 0)
    }

    // MARK: - Cache-write TTL tiers

    /// 1-hour cache entries bill at 2x input, 5-minute at 1.25x. Current Claude Code
    /// writes almost exclusively 1-hour entries, so charging everything at 1.25x
    /// understated cost across the board.
    func test_cacheWrite_billedByTTL() {
        let oneHour = TokenUsage(input: 0, output: 0, cacheWrite5m: 0, cacheWrite1h: 1_000_000, cacheRead: 0)
        XCTAssertEqual(Pricing.cost(model: "claude-opus-4-8", usage: oneHour), 10.0, accuracy: 0.0001)

        let fiveMinute = TokenUsage(input: 0, output: 0, cacheWrite5m: 1_000_000, cacheWrite1h: 0, cacheRead: 0)
        XCTAssertEqual(Pricing.cost(model: "claude-opus-4-8", usage: fiveMinute), 6.25, accuracy: 0.0001)
    }

    /// The legacy initializer has no TTL information; it must stay on the cheaper
    /// 5-minute rate so old callers don't silently start over-charging.
    func test_legacyCacheWriteInit_usesFiveMinuteRate() {
        let usage = TokenUsage(input: 0, output: 0, cacheWrite: 1_000_000, cacheRead: 0)
        XCTAssertEqual(Pricing.cost(model: "claude-opus-4-8", usage: usage), 6.25, accuracy: 0.0001)
        XCTAssertEqual(usage.cacheWrite, 1_000_000)
    }

    func test_utilizationTokens_countBothCacheWriteTiers() {
        let usage = TokenUsage(input: 100, output: 50, cacheWrite5m: 25, cacheWrite1h: 75, cacheRead: 99999)
        XCTAssertEqual(usage.cacheWrite, 100)
        XCTAssertEqual(usage.utilizationTokens, 250)
    }

    func test_tokenSum_excludesCacheRead() {
        let usage = TokenUsage(input: 100, output: 50, cacheWrite: 25, cacheRead: 99999)
        XCTAssertEqual(usage.utilizationTokens, 175)
    }
}
