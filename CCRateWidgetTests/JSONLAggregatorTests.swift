import XCTest

final class JSONLAggregatorTests: XCTestCase {
    var rootDir: URL!
    var storeDir: URL!
    var store: AppGroupStore!
    var aggregator: JSONLAggregator!

    override func setUp() {
        super.setUp()
        rootDir  = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("agg-root-\(UUID().uuidString)")
        storeDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("agg-store-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: rootDir,  withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        store = AppGroupStore(containerURL: storeDir)
        aggregator = JSONLAggregator(rootDir: rootDir, store: store)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: rootDir)
        try? FileManager.default.removeItem(at: storeDir)
        super.tearDown()
    }

    private func writeFile(_ relPath: String, _ contents: String) {
        let url = rootDir.appendingPathComponent(relPath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func assistantLine(ts: String, cwd: String, model: String, inTok: Int, outTok: Int) -> String {
        """
        {"type":"assistant","timestamp":"\(ts)","sessionId":"s","cwd":"\(cwd)","message":{"model":"\(model)","usage":{"input_tokens":\(inTok),"output_tokens":\(outTok)}}}
        """
    }

    func test_aggregate_singleFile_fiveHourWindow() throws {
        let now = Date()
        let inWindow  = AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-60))
        let outOfWindow = AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-6 * 3600))
        let lines = [
            assistantLine(ts: inWindow,    cwd: "/Users/dk/dev/a", model: "claude-opus-4-7",  inTok: 100, outTok: 50),
            assistantLine(ts: outOfWindow, cwd: "/Users/dk/dev/a", model: "claude-opus-4-7",  inTok: 999, outTok: 999),
        ].joined(separator: "\n") + "\n"
        writeFile("projA/session1.jsonl", lines)

        let snapshot = try aggregator.aggregate(now: now)
        XCTAssertEqual(snapshot.fiveHourTokens, 150)
    }

    func test_aggregate_corruptLine_skipped() throws {
        let now = Date()
        let good = assistantLine(ts: AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-60)),
                                  cwd: "/p", model: "claude-opus-4-7", inTok: 10, outTok: 20)
        writeFile("p/s.jsonl", "garbage\n" + good + "\n")
        let snap = try aggregator.aggregate(now: now)
        XCTAssertEqual(snap.fiveHourTokens, 30)
    }

    func test_aggregate_sonnetWindow_onlyCountsSonnet() throws {
        let now = Date()
        let ts = AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-3600))
        writeFile("p/s.jsonl",
            assistantLine(ts: ts, cwd: "/p", model: "claude-opus-4-7",  inTok: 100, outTok: 0) + "\n" +
            assistantLine(ts: ts, cwd: "/p", model: "claude-sonnet-4-6", inTok: 200, outTok: 0) + "\n")
        let snap = try aggregator.aggregate(now: now)
        XCTAssertEqual(snap.sevenDayTokens, 300)
        XCTAssertEqual(snap.sevenDaySonnetTokens, 200)
    }

    func test_aggregate_perProject_mergesAcrossFiles() throws {
        let now = Date()
        let ts = AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-60))
        writeFile("a/1.jsonl", assistantLine(ts: ts, cwd: "/Users/dk/dev/a", model: "claude-opus-4-7", inTok: 100, outTok: 0) + "\n")
        writeFile("a/2.jsonl", assistantLine(ts: ts, cwd: "/Users/dk/dev/a", model: "claude-opus-4-7", inTok: 50,  outTok: 0) + "\n")
        let snap = try aggregator.aggregate(now: now)
        let aEntry = snap.projects.entries.first { $0.path == "/Users/dk/dev/a" }
        XCTAssertEqual(aEntry?.tokens, 150)
    }
}

/// Test-only ISO formatter; named to avoid colliding with anything in Shared/.
enum AggTestISOFormatter {
    static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
