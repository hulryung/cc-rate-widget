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
