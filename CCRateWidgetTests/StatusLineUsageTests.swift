import XCTest

final class StatusLineUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func payload(ageSeconds: Double, limits: [String: Any]) -> [String: Any] {
        ["written_at": now.timeIntervalSince1970 - ageSeconds, "rate_limits": limits]
    }

    private let bothWindows: [String: Any] = [
        "five_hour": ["used_percentage": 23.5, "resets_at": 1_800_003_600],
        "seven_day": ["used_percentage": 41.0, "resets_at": 1_800_432_000],
    ]

    func test_parses_bothWindows_percentageBecomesFraction() {
        let u = StatusLineUsage.parse(payload(ageSeconds: 60, limits: bothWindows), now: now)
        XCTAssertEqual(u?.fiveHour?.utilization ?? 0, 0.235, accuracy: 0.0001)
        XCTAssertEqual(u?.sevenDay?.utilization ?? 0, 0.41, accuracy: 0.0001)
        XCTAssertEqual(u?.sevenDay?.resetsAt, Date(timeIntervalSince1970: 1_800_432_000))
    }

    /// Claude Code documents that either window can be absent on its own.
    func test_oneWindowAlone_isEnough() {
        let only = ["seven_day": ["used_percentage": 41.0, "resets_at": 1_800_432_000]]
        let u = StatusLineUsage.parse(payload(ageSeconds: 60, limits: only), now: now)
        XCTAssertNotNil(u)
        XCTAssertNil(u?.fiveHour)
        XCTAssertNotNil(u?.sevenDay)
    }

    /// A window without resets_at still carries its percentage; the caller decides that it
    /// then has nothing to anchor local token counts to.
    func test_windowWithoutResetsAt_keepsPercentage() {
        let noReset = ["five_hour": ["used_percentage": 12.0]]
        let u = StatusLineUsage.parse(payload(ageSeconds: 60, limits: noReset), now: now)
        XCTAssertEqual(u?.fiveHour?.utilization ?? 0, 0.12, accuracy: 0.0001)
        XCTAssertNil(u?.fiveHour?.resetsAt)
    }

    func test_stale_isRejected() {
        let old = payload(ageSeconds: StatusLineUsage.staleAfter + 1, limits: bothWindows)
        XCTAssertNil(StatusLineUsage.parse(old, now: now),
                     "an hour-old percentage may describe a window that has since rolled over")
    }

    func test_justInsideTheWindow_isAccepted() {
        let fresh = payload(ageSeconds: StatusLineUsage.staleAfter - 1, limits: bothWindows)
        XCTAssertNotNil(StatusLineUsage.parse(fresh, now: now))
    }

    /// A file stamped in the future means a clock disagreement, not fresh data.
    func test_futureStamp_isRejected() {
        XCTAssertNil(StatusLineUsage.parse(payload(ageSeconds: -600, limits: bothWindows), now: now))
    }

    func test_noWindows_isNil() {
        XCTAssertNil(StatusLineUsage.parse(payload(ageSeconds: 60, limits: [:]), now: now),
                     "a session before its first API response carries neither window")
    }

    func test_missingTimestamp_isNil() {
        XCTAssertNil(StatusLineUsage.parse(["rate_limits": bothWindows], now: now))
    }

    /// End to end through the file, since that is how the app actually reads it.
    func test_read_fromDisk() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let json = try JSONSerialization.data(withJSONObject: payload(ageSeconds: 30, limits: bothWindows))
        try json.write(to: dir.appendingPathComponent(StatusLineUsage.fileName))

        let u = StatusLineUsage.read(from: dir, now: now)
        XCTAssertEqual(u?.sevenDay?.utilization ?? 0, 0.41, accuracy: 0.0001)
        XCTAssertNil(StatusLineUsage.read(from: dir.appendingPathComponent("nope"), now: now))
    }
}
