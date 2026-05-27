import XCTest

final class ModelsTests: XCTestCase {
    func test_rateDataSource_rawValues() {
        XCTAssertEqual(RateDataSource.jsonl.rawValue, "jsonl")
        XCTAssertEqual(RateDataSource.oauth.rawValue, "oauth")
        XCTAssertEqual(RateDataSource.hybrid.rawValue, "hybrid")
        XCTAssertEqual(RateDataSource.partial.rawValue, "partial")
        XCTAssertEqual(RateDataSource.noLocalData.rawValue, "no_local_data")
    }

    func test_projectBreakdown_topN_returnsTop3SortedDescending() {
        let breakdown = ProjectBreakdown(entries: [
            .init(displayName: "a", path: "/a", tokens: 100, cost: 0.1),
            .init(displayName: "b", path: "/b", tokens: 500, cost: 0.5),
            .init(displayName: "c", path: "/c", tokens: 300, cost: 0.3),
            .init(displayName: "d", path: "/d", tokens: 50,  cost: 0.05),
        ])
        let top = breakdown.topN(3).map(\.displayName)
        XCTAssertEqual(top, ["b", "c", "a"])
    }
}

extension ModelsTests {
    func test_inferredLimits_decodesFromEmptyJSON() throws {
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(InferredLimits.self, from: json)
        XCTAssertEqual(decoded.weeklyMaxObserved, 0)
        XCTAssertEqual(decoded.fiveHourMaxObserved, 0)
        XCTAssertNil(decoded.fiveHourTokens)
        XCTAssertNil(decoded.manualPlanTier)
    }

    func test_inferredLimits_decodesFromPartialJSON() throws {
        let json = #"{"weeklyMaxObserved": 1234, "manualPlanTier": "max5"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(InferredLimits.self, from: json)
        XCTAssertEqual(decoded.weeklyMaxObserved, 1234)
        XCTAssertEqual(decoded.manualPlanTier, .max5)
        XCTAssertEqual(decoded.fiveHourMaxObserved, 0)
    }

    func test_projectBreakdown_decodesFromMissingAliases() throws {
        let json = #"{"entries":[]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ProjectBreakdown.self, from: json)
        XCTAssertTrue(decoded.aliases.isEmpty)
        XCTAssertTrue(decoded.entries.isEmpty)
    }

    func test_inferredLimits_roundTripsThroughJSON() throws {
        let original = InferredLimits(weeklyMaxObserved: 99, manualPlanTier: .pro)
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(InferredLimits.self, from: data)
        XCTAssertEqual(back.weeklyMaxObserved, 99)
        XCTAssertEqual(back.manualPlanTier, .pro)
    }
}
