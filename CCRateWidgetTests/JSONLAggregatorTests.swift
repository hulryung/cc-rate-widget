import XCTest

final class JSONLAggregatorTests: XCTestCase {
    var rootDir: URL!
    var storeDir: URL!
    var store: LocalStore!
    var aggregator: JSONLAggregator!

    override func setUp() {
        super.setUp()
        rootDir  = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("agg-root-\(UUID().uuidString)")
        storeDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("agg-store-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: rootDir,  withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        store = LocalStore(containerURL: storeDir)
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

    // MARK: - Schema migration

    /// Stored events carry a precomputed cost, so a pricing fix can't repair them in
    /// place — a version bump has to force them to be re-read from source. This is what
    /// repairs already-ingested events after the Claude 5 pricing fix.
    func test_aggregate_schemaBump_recomputesStoredCosts() throws {
        let now = Date()
        let ts = AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-60))
        writeFile("p/s.jsonl", assistantLine(ts: ts, cwd: "/p", model: "claude-opus-4-8",
                                             inTok: 1_000_000, outTok: 0) + "\n")

        // Simulate a store written by the old build: correct offsets, but a cost of 0
        // baked in (which is exactly what an unpriced model produced).
        _ = try aggregator.aggregate(now: now)
        var events = try store.readEvents()
        let path = try XCTUnwrap(events.keys.first)
        events[path] = events[path]!.map {
            StoredEvent(t: $0.t, tokens: $0.tokens, family: $0.family, cost: 0,
                        project: $0.project, id: $0.id)
        }
        try store.writeEvents(events)
        try store.writeSchemaVersion(1)

        // Without a rescan the stale zero would survive; the bump must re-read the file.
        let snap = try JSONLAggregator(rootDir: rootDir, store: store).aggregate(now: now)
        XCTAssertEqual(snap.fiveHourCost, 5.0, accuracy: 0.0001)
        XCTAssertEqual(snap.fiveHourTokens, 1_000_000)
        XCTAssertEqual(store.readSchemaVersion(), LocalStore.currentSchemaVersion)
    }

    /// The rescan must not double-count: re-reading a file whose events are already
    /// stored has to replace them, not append to them.
    func test_aggregate_schemaBump_doesNotDoubleCount() throws {
        let now = Date()
        let ts = AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-60))
        writeFile("p/s.jsonl", assistantLine(ts: ts, cwd: "/p", model: "claude-opus-4-8",
                                             inTok: 100, outTok: 50) + "\n")

        let first = try aggregator.aggregate(now: now)
        try store.writeSchemaVersion(1)
        let afterMigration = try JSONLAggregator(rootDir: rootDir, store: store).aggregate(now: now)

        XCTAssertEqual(afterMigration.fiveHourTokens, first.fiveHourTokens)
        XCTAssertEqual(afterMigration.fiveHourCost, first.fiveHourCost, accuracy: 0.0001)
    }

    /// Once migrated, ordinary ticks must not keep rescanning from byte 0.
    func test_aggregate_schemaVersionPersists_soMigrationRunsOnce() throws {
        let now = Date()
        let ts = AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-60))
        writeFile("p/s.jsonl", assistantLine(ts: ts, cwd: "/p", model: "claude-opus-4-8",
                                             inTok: 100, outTok: 50) + "\n")

        _ = try aggregator.aggregate(now: now)
        XCTAssertEqual(store.readSchemaVersion(), LocalStore.currentSchemaVersion)

        let offsetsAfterFirst = try store.readOffsets()
        _ = try aggregator.aggregate(now: now)
        XCTAssertEqual(try store.readOffsets(), offsetsAfterFirst)
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
        XCTAssertEqual(snap.sevenDayByFamily["sonnet"]?.tokens, 200)
    }

    /// Every family is counted, not just Sonnet. A `sonnet: Bool` flag discarded the rest,
    /// so Anthropic's scoped "Weekly · Fable" window had no local tokens and showed 0.
    func test_aggregate_splitsAllFamiliesNotJustSonnet() throws {
        let now = Date()
        let ts = AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-3600))
        writeFile("p/s.jsonl",
            assistantLine(ts: ts, cwd: "/p", model: "claude-fable-5",   inTok: 400, outTok: 0) + "\n" +
            assistantLine(ts: ts, cwd: "/p", model: "claude-opus-4-8",  inTok: 100, outTok: 0) + "\n" +
            assistantLine(ts: ts, cwd: "/p", model: "claude-sonnet-5",  inTok: 200, outTok: 0) + "\n")
        let snap = try aggregator.aggregate(now: now)
        XCTAssertEqual(snap.sevenDayByFamily["fable"]?.tokens, 400)
        XCTAssertEqual(snap.sevenDayByFamily["opus"]?.tokens, 100)
        XCTAssertEqual(snap.sevenDayByFamily["sonnet"]?.tokens, 200)
        XCTAssertEqual(snap.sevenDayTokens, 700)
    }

    /// Family cost is tracked alongside tokens so a scoped window can show dollars too.
    func test_aggregate_familyCarriesCost() throws {
        let now = Date()
        let ts = AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-3600))
        writeFile("p/s.jsonl", assistantLine(ts: ts, cwd: "/p", model: "claude-fable-5",
                                             inTok: 1_000_000, outTok: 0) + "\n")
        let snap = try aggregator.aggregate(now: now)
        XCTAssertEqual(snap.sevenDayByFamily["fable"]?.cost ?? 0, 10.0, accuracy: 0.0001)
    }

    /// An unrecognised model contributes to the totals but not to any family bucket —
    /// better than inventing a family that no window will ever match.
    func test_aggregate_unknownFamily_isNotBucketed() throws {
        let now = Date()
        let ts = AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-3600))
        writeFile("p/s.jsonl", assistantLine(ts: ts, cwd: "/p", model: "<synthetic>",
                                             inTok: 50, outTok: 0) + "\n")
        let snap = try aggregator.aggregate(now: now)
        XCTAssertEqual(snap.sevenDayTokens, 50)
        XCTAssertTrue(snap.sevenDayByFamily.isEmpty)
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

    private func append(_ relPath: String, _ contents: String) {
        let url = rootDir.appendingPathComponent(relPath)
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        try? h.seekToEnd()
        h.write(contents.data(using: .utf8)!)
        try? h.close()
    }

    // REGRESSION: the rolling window must reflect ALL in-window events on every tick,
    // not just the lines appended since the previous tick. Pre-fix, tick 2 only saw the
    // newly-appended line because offsets had advanced to EOF.
    func test_multiTick_rollingWindow_retainsEarlierEvents() throws {
        let now = Date()
        let ts1 = AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-120))
        writeFile("p/s.jsonl", assistantLine(ts: ts1, cwd: "/p", model: "claude-opus-4-7", inTok: 100, outTok: 0) + "\n")
        let snap1 = try aggregator.aggregate(now: now)
        XCTAssertEqual(snap1.fiveHourTokens, 100)

        // A new event is appended; tick 2 must report BOTH events (both still in-window).
        let ts2 = AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-60))
        append("p/s.jsonl", assistantLine(ts: ts2, cwd: "/p", model: "claude-opus-4-7", inTok: 25, outTok: 0) + "\n")
        let snap2 = try aggregator.aggregate(now: now)
        XCTAssertEqual(snap2.fiveHourTokens, 125)
        XCTAssertEqual(snap2.sevenDayTokens, 125)
    }

    // A tick with no new lines must still report the full retained window.
    func test_multiTick_noNewLines_stillReportsWindow() throws {
        let now = Date()
        let ts = AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-60))
        writeFile("p/s.jsonl", assistantLine(ts: ts, cwd: "/p", model: "claude-opus-4-7", inTok: 200, outTok: 0) + "\n")
        XCTAssertEqual(try aggregator.aggregate(now: now).fiveHourTokens, 200)
        // Second tick reads zero new bytes but must still see the stored event.
        XCTAssertEqual(try aggregator.aggregate(now: now).fiveHourTokens, 200)
    }

    // Events fall out of the window as time advances between ticks.
    func test_multiTick_ageOut_dropsExpiredEvents() throws {
        let base = Date()
        let ts = AggTestISOFormatter.shared.string(from: base.addingTimeInterval(-3600)) // 1h ago at base
        writeFile("p/s.jsonl", assistantLine(ts: ts, cwd: "/p", model: "claude-opus-4-7", inTok: 100, outTok: 0) + "\n")
        XCTAssertEqual(try aggregator.aggregate(now: base).fiveHourTokens, 100)

        // 8 days later: the event is outside the 7-day window and must be gone.
        let later = base.addingTimeInterval(8 * 86400)
        let snap = try aggregator.aggregate(now: later)
        XCTAssertEqual(snap.sevenDayTokens, 0)
        XCTAssertEqual(snap.fiveHourTokens, 0)
    }

    // File truncation/rotation must not double-count: the bucket is rebuilt from 0.
    func test_fileTruncation_doesNotDoubleCount() throws {
        let now = Date()
        let ts = AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-60))
        writeFile("p/s.jsonl",
            assistantLine(ts: ts, cwd: "/p", model: "claude-opus-4-7", inTok: 100, outTok: 0) + "\n" +
            assistantLine(ts: ts, cwd: "/p", model: "claude-opus-4-7", inTok: 100, outTok: 0) + "\n")
        XCTAssertEqual(try aggregator.aggregate(now: now).fiveHourTokens, 200)

        // Rewrite the file smaller (rotation). Atomic write replaces contents.
        writeFile("p/s.jsonl", assistantLine(ts: ts, cwd: "/p", model: "claude-opus-4-7", inTok: 5, outTok: 0) + "\n")
        XCTAssertEqual(try aggregator.aggregate(now: now).fiveHourTokens, 5)
    }

    // A deleted file's events must not linger in the rolling store.
    func test_deletedFile_eventsAreEvicted() throws {
        let now = Date()
        let ts = AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-60))
        writeFile("p/s.jsonl", assistantLine(ts: ts, cwd: "/p", model: "claude-opus-4-7", inTok: 100, outTok: 0) + "\n")
        XCTAssertEqual(try aggregator.aggregate(now: now).fiveHourTokens, 100)

        try FileManager.default.removeItem(at: rootDir.appendingPathComponent("p/s.jsonl"))
        XCTAssertEqual(try aggregator.aggregate(now: now).fiveHourTokens, 0)
    }

    private func assistantLineWithID(ts: String, cwd: String, model: String, inTok: Int, msgID: String, reqID: String) -> String {
        """
        {"type":"assistant","timestamp":"\(ts)","sessionId":"s","requestId":"\(reqID)","cwd":"\(cwd)","message":{"id":"\(msgID)","model":"\(model)","usage":{"input_tokens":\(inTok),"output_tokens":0}}}
        """
    }

    // REGRESSION: Claude Code logs the same assistant turn in multiple files; counting
    // every line double-counts. Same (messageId, requestId) across two files = counted once.
    func test_dedupe_sameMessageAcrossFiles_countedOnce() throws {
        let now = Date()
        let ts = AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-60))
        let line = assistantLineWithID(ts: ts, cwd: "/p", model: "claude-opus-4-7", inTok: 100, msgID: "msg_abc", reqID: "req_1")
        writeFile("a/session.jsonl", line + "\n")
        writeFile("b/summary.jsonl", line + "\n")   // duplicate of the same turn
        let snap = try aggregator.aggregate(now: now)
        XCTAssertEqual(snap.fiveHourTokens, 100, "duplicate of same message must be counted once")
        XCTAssertEqual(snap.projects.entries.reduce(0) { $0 + $1.tokens }, 100)
    }

    func test_dedupe_differentMessages_bothCounted() throws {
        let now = Date()
        let ts = AggTestISOFormatter.shared.string(from: now.addingTimeInterval(-60))
        writeFile("p/s.jsonl",
            assistantLineWithID(ts: ts, cwd: "/p", model: "claude-opus-4-7", inTok: 100, msgID: "m1", reqID: "r1") + "\n" +
            assistantLineWithID(ts: ts, cwd: "/p", model: "claude-opus-4-7", inTok: 50,  msgID: "m2", reqID: "r2") + "\n")
        XCTAssertEqual(try aggregator.aggregate(now: now).fiveHourTokens, 150)
    }

    func test_computeSnapshot_typicalPeak_p90OfPastBlocks() {
        let now = Date()
        let nowT = now.timeIntervalSince1970
        let blockLen = 5.0 * 3600
        // 5 past 5-hour blocks with varying totals; current block excluded.
        var events: [StoredEvent] = []
        let pastTotals = [100, 200, 300, 400, 5000]   // P90 (nearest-rank) → 5000
        for (i, total) in pastTotals.enumerated() {
            let t = nowT - Double(i + 1) * blockLen   // each in a distinct earlier block
            events.append(StoredEvent(t: t, tokens: total, family: "opus", cost: 0, project: "/p", id: "b\(i)"))
        }
        let snap = JSONLAggregator.computeSnapshot(events: events, now: now)
        XCTAssertNotNil(snap.typicalFiveHourPeak)
        XCTAssertEqual(snap.typicalFiveHourPeak, 5000)
    }

    /// Local noon today, so a day bucket can never be one hour either side of a boundary.
    private func localNoonToday() -> Date {
        let base = Date()
        let tz = Double(TimeZone.current.secondsFromGMT(for: base))
        let dayIndex = Int((base.timeIntervalSince1970 + tz) / 86400)
        return Date(timeIntervalSince1970: Double(dayIndex) * 86400 - tz + 12 * 3600)
    }

    func test_computeSnapshot_weeklyPace_sevenTimesHeaviestWholeDay() {
        let now = localNoonToday()
        let noon = now.timeIntervalSince1970
        var events = [
            // Three whole days back, heaviest last.
            StoredEvent(t: noon - 1 * 86400, tokens: 100, family: "opus", cost: 0, project: "/p", id: "d1"),
            StoredEvent(t: noon - 2 * 86400, tokens: 200, family: "opus", cost: 0, project: "/p", id: "d2"),
            StoredEvent(t: noon - 3 * 86400, tokens: 300, family: "opus", cost: 0, project: "/p", id: "d3"),
        ]
        // Today is still filling and the oldest day is cut off by the 7-day retention;
        // neither is a whole day, so neither may set the pace however big it is.
        events.append(StoredEvent(t: noon - 3600,     tokens: 9_000, family: "opus", cost: 0, project: "/p", id: "today"))
        events.append(StoredEvent(t: noon - 7 * 86400 + 60, tokens: 9_000, family: "opus", cost: 0, project: "/p", id: "edge"))

        let snap = JSONLAggregator.computeSnapshot(events: events, now: now)
        XCTAssertEqual(snap.typicalWeeklyPeak, 300 * 7)
    }

    func test_computeSnapshot_weeklyPace_nilWhenTooFewWholeDays() {
        let now = localNoonToday()
        let noon = now.timeIntervalSince1970
        let events = [
            StoredEvent(t: noon - 1 * 86400, tokens: 100, family: "opus", cost: 0, project: "/p", id: "d1"),
            StoredEvent(t: noon - 2 * 86400, tokens: 200, family: "opus", cost: 0, project: "/p", id: "d2"),
            StoredEvent(t: noon - 3600,      tokens: 900, family: "opus", cost: 0, project: "/p", id: "today"),
        ]
        XCTAssertNil(JSONLAggregator.computeSnapshot(events: events, now: now).typicalWeeklyPeak)
    }

    func test_computeSnapshot_typicalPeak_nilWhenTooFewBlocks() {
        let now = Date()
        let nowT = now.timeIntervalSince1970
        let events = [
            StoredEvent(t: nowT - 6 * 3600, tokens: 100, family: "opus", cost: 0, project: "/p", id: "x"),
        ]
        XCTAssertNil(JSONLAggregator.computeSnapshot(events: events, now: now).typicalFiveHourPeak)
    }

    // Pure window math, isolated from the filesystem.
    func test_computeSnapshot_windows() {
        let now = Date()
        let nowT = now.timeIntervalSince1970
        let events = [
            StoredEvent(t: nowT - 60,         tokens: 100, family: "opus", cost: 0.1, project: "/a"),
            StoredEvent(t: nowT - 6 * 3600,   tokens: 200, family: "sonnet",  cost: 0.2, project: "/a"), // outside 5h, in 7d
            StoredEvent(t: nowT - 8 * 86400,  tokens: 999, family: "opus", cost: 9.9, project: "/a"), // outside 7d
        ]
        let snap = JSONLAggregator.computeSnapshot(events: events, now: now)
        XCTAssertEqual(snap.fiveHourTokens, 100)
        XCTAssertEqual(snap.sevenDayTokens, 300)
        XCTAssertEqual(snap.sevenDayByFamily["sonnet"]?.tokens, 200)
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

final class SnapshotTotalsTests: XCTestCase {
    private func event(_ agoSeconds: TimeInterval, tokens: Int, cost: Double, family: String,
                       now: Date) -> StoredEvent {
        StoredEvent(t: now.addingTimeInterval(-agoSeconds).timeIntervalSince1970,
                    tokens: tokens, family: family, cost: cost, project: "/p", id: UUID().uuidString)
    }

    /// Anthropic's windows are fixed blocks with their own start. Counting our rolling
    /// window instead is how a card came to read "99.7M tok" beside a freshly-reset "0%".
    func test_totals_sinceAnInstant_excludesEarlierEvents() {
        let now = Date()
        let snap = JSONLAggregator.computeSnapshot(events: [
            event(30 * 60, tokens: 100, cost: 1, family: "opus", now: now),   // inside
            event(6 * 3600, tokens: 900, cost: 9, family: "opus", now: now),  // before the block
        ], now: now)

        let t = snap.totals(since: now.addingTimeInterval(-3600))
        XCTAssertEqual(t.tokens, 100)
        XCTAssertEqual(t.cost, 1, accuracy: 0.0001)
    }

    func test_totals_filtersByFamily() {
        let now = Date()
        let snap = JSONLAggregator.computeSnapshot(events: [
            event(60, tokens: 400, cost: 4, family: "fable", now: now),
            event(60, tokens: 100, cost: 1, family: "opus", now: now),
        ], now: now)

        XCTAssertEqual(snap.totals(since: now.addingTimeInterval(-3600), family: "fable").tokens, 400)
        XCTAssertEqual(snap.totals(since: now.addingTimeInterval(-3600), family: "opus").tokens, 100)
        XCTAssertEqual(snap.totals(since: now.addingTimeInterval(-3600)).tokens, 500)
    }

    /// Just after a reset the block is empty, and the card must say so rather than
    /// reporting the previous week's rolling total.
    func test_totals_immediatelyAfterReset_isZero() {
        let now = Date()
        let snap = JSONLAggregator.computeSnapshot(events: [
            event(2 * 3600, tokens: 5_000, cost: 50, family: "opus", now: now),
        ], now: now)
        XCTAssertEqual(snap.totals(since: now.addingTimeInterval(-60)).tokens, 0)
        XCTAssertEqual(snap.sevenDayTokens, 5_000)   // the rolling figure is unchanged
    }

    /// Deduplication has to happen before the events are kept, or a totals() call
    /// double-counts what the window sums got right.
    func test_totals_respectsDeduplication() {
        let now = Date()
        let t = now.addingTimeInterval(-60).timeIntervalSince1970
        let dup = StoredEvent(t: t, tokens: 100, family: "opus", cost: 1, project: "/p", id: "same")
        let snap = JSONLAggregator.computeSnapshot(events: [dup, dup], now: now)
        XCTAssertEqual(snap.totals(since: now.addingTimeInterval(-3600)).tokens, 100)
    }
}
