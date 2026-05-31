import XCTest

final class ClaudePlanTests: XCTestCase {
    func test_friendlyName_mapsKnownTiers() {
        XCTAssertEqual(ClaudePlan.friendlyName(tier: "default_claude_max_20x"), "Max 20x")
        XCTAssertEqual(ClaudePlan.friendlyName(tier: "default_claude_max_5x"), "Max 5x")
        XCTAssertEqual(ClaudePlan.friendlyName(tier: "default_claude_pro"), "Pro")
        XCTAssertEqual(ClaudePlan.friendlyName(tier: "some_team_tier"), "Team")
    }

    func test_friendlyName_nilForUnknownOrMissing() {
        XCTAssertNil(ClaudePlan.friendlyName(tier: nil))
        XCTAssertNil(ClaudePlan.friendlyName(tier: "mystery_tier"))
    }

    func test_detect_readsFromCredentialsFile() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeplan-\(UUID().uuidString)")
        let dir = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let json = #"{"claudeAiOauth":{"rateLimitTier":"default_claude_max_20x"}}"#
        try json.write(to: dir.appendingPathComponent(".credentials.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ClaudePlan.detect(home: home), "Max 20x")
    }

    func test_detect_nilWhenMissing() {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeplan-missing-\(UUID().uuidString)")
        XCTAssertNil(ClaudePlan.detect(home: home))
    }
}

final class OfficialUsageTests: XCTestCase {
    func test_parse_realResponseShape() throws {
        let json = #"""
        {"five_hour":{"utilization":20.0,"resets_at":"2026-05-31T04:50:00.873219+00:00"},
         "seven_day":{"utilization":18.0,"resets_at":"2026-06-03T13:00:00.873248+00:00"},
         "seven_day_opus":null,
         "seven_day_sonnet":{"utilization":1.0,"resets_at":"2026-06-03T12:59:59.873254+00:00"},
         "extra_usage":{"is_enabled":true,"monthly_limit":10000,"used_credits":0.0,"utilization":null}}
        """#
        let u = try XCTUnwrap(OfficialUsage.parse(Data(json.utf8)))
        XCTAssertEqual(u.fiveHour, 0.20, accuracy: 0.0001)
        XCTAssertEqual(u.sevenDay, 0.18, accuracy: 0.0001)
        XCTAssertEqual(u.sevenDaySonnet, 0.01, accuracy: 0.0001)
        XCTAssertNotNil(u.fiveHourResetsAt)
    }

    func test_parse_garbageReturnsNil() {
        XCTAssertNil(OfficialUsage.parse(Data("not json".utf8)))
        XCTAssertNil(OfficialUsage.parse(Data("{}".utf8)))
    }

    func test_withOfficial_overlaysUtilizationKeepsTokens() {
        let local = CategoryData(tokens: 3_000_000, cost: 80, resetsAt: nil, limitTokens: 4_000_000, limitKind: .typicalPeak)
        let o = local.withOfficial(0.20, resetsAt: nil)
        XCTAssertEqual(o.utilization, 0.20)       // official wins
        XCTAssertEqual(o.tokens, 3_000_000)        // local tokens kept
        XCTAssertEqual(o.limitKind, .official)
    }
}
