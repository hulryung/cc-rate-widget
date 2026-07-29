import XCTest

final class RateDataFallbackTests: XCTestCase {
    /// The fallback when no snapshot is on disk. It must read as "no data" — the sample
    /// `placeholder` would otherwise be shown as live usage.
    func test_unavailable_isEmptyAndFlaggedNoLocalData() {
        let r = RateData.unavailable
        XCTAssertEqual(r.status, .noLocalData)
        XCTAssertEqual(r.source, .noLocalData)
        XCTAssertTrue(r.windows.isEmpty)
        XCTAssertNil(r.weekly)
        XCTAssertNil(r.session)
        XCTAssertNil(r.planName)
    }

    /// Guards the mistake being fixed: the sample claims to be active usage, so it must
    /// never be what a data-less surface renders.
    func test_placeholder_isNotMistakenForNoData() {
        XCTAssertEqual(RateData.placeholder.status, .active)
        XCTAssertGreaterThan(RateData.placeholder.weekly?.data.tokens ?? 0, 0)
        XCTAssertNotEqual(RateData.placeholder.status, RateData.unavailable.status)
    }

    /// The menu bar reads one specific window out of a list whose length varies, so the
    /// lookup must be by id rather than position.
    func test_weeklyAndSession_foundByIdRegardlessOfOrder() {
        let cat = CategoryData(tokens: 1, cost: 0, resetsAt: nil)
        let r = RateData(
            windows: [
                UsageWindow(id: "weekly_scoped:Fable", title: "Weekly · Fable", subtitle: "7 days", data: cat),
                UsageWindow(id: RateData.sessionID, title: "Session", subtitle: "5 hours", data: cat),
                UsageWindow(id: RateData.weeklyID, title: "Weekly", subtitle: "7 days", data: cat),
            ],
            fetchedAt: Date(), status: .active, source: .oauth)
        XCTAssertEqual(r.weekly?.id, RateData.weeklyID)
        XCTAssertEqual(r.session?.id, RateData.sessionID)
    }

    /// With no all-model window, any weekly one is better than showing nothing.
    func test_weekly_fallsBackToAScopedWindow() {
        let cat = CategoryData(tokens: 1, cost: 0, resetsAt: nil)
        let r = RateData(
            windows: [UsageWindow(id: "weekly_scoped:Fable", title: "Weekly · Fable",
                                  subtitle: "7 days", data: cat)],
            fetchedAt: Date(), status: .active, source: .oauth)
        XCTAssertEqual(r.weekly?.id, "weekly_scoped:Fable")
    }
}

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
    func test_projectBreakdown_decodesFromMissingAliases() throws {
        let json = #"{"entries":[]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ProjectBreakdown.self, from: json)
        XCTAssertTrue(decoded.aliases.isEmpty)
        XCTAssertTrue(decoded.entries.isEmpty)
    }

    func test_categoryData_holdsAbsoluteUsage() {
        let c = CategoryData(tokens: 2_400_000, cost: 18.50, resetsAt: nil)
        XCTAssertEqual(c.tokens, 2_400_000)
        XCTAssertEqual(c.cost, 18.50, accuracy: 0.001)
        XCTAssertNil(c.resetsAt)
    }

    func test_rateData_placeholder_isActiveLocal() {
        XCTAssertEqual(RateData.placeholder.status, .active)
        XCTAssertEqual(RateData.placeholder.source, .jsonl)
        XCTAssertGreaterThan(RateData.placeholder.weekly?.data.tokens ?? 0, 0)
    }
}
