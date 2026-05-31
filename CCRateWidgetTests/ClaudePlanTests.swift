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
