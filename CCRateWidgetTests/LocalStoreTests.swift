import XCTest

final class LocalStoreTests: XCTestCase {
    var tmpDir: URL!
    var store: LocalStore!

    override func setUp() {
        super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LocalStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = LocalStore(containerURL: tmpDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    func test_writeAndRead_rate_roundTrip() throws {
        let original = RateData(
            session: CategoryData(tokens: 100_000, cost: 1.5, resetsAt: Date(timeIntervalSince1970: 1_000_000)),
            weekly: CategoryData(tokens: 5_000_000, cost: 42.0, resetsAt: nil),
            weeklySonnet: CategoryData(tokens: 250_000, cost: 0, resetsAt: nil),
            fetchedAt: Date(timeIntervalSince1970: 2_000_000),
            status: .active,
            source: .jsonl
        )
        try store.writeRate(original)
        let loaded = try XCTUnwrap(store.readRate())
        XCTAssertEqual(loaded.session.tokens, 100_000)
        XCTAssertEqual(loaded.weekly.cost, 42.0, accuracy: 0.001)
        XCTAssertEqual(loaded.session.resetsAt?.timeIntervalSince1970, 1_000_000)
        XCTAssertNil(loaded.weekly.resetsAt)
        XCTAssertEqual(loaded.status, .active)
        XCTAssertEqual(loaded.source, .jsonl)
    }

    func test_read_missingFile_returnsNil() throws {
        XCTAssertNil(try store.readRate())
        XCTAssertNil(try store.readProjects())
    }

    func test_read_corruptFile_throws() throws {
        let url = tmpDir.appendingPathComponent("rate.json")
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.readRate())
    }

    func test_offsets_roundTrip() throws {
        try store.writeOffsets(["/a.jsonl": 100, "/b.jsonl": 250])
        let loaded = try store.readOffsets()
        XCTAssertEqual(loaded, ["/a.jsonl": 100, "/b.jsonl": 250])
    }

    func test_events_roundTrip() throws {
        let events = ["/p/s.jsonl": [StoredEvent(t: 12345, tokens: 100, sonnet: false, cost: 0.1, project: "/p")]]
        try store.writeEvents(events)
        let loaded = try store.readEvents()
        XCTAssertEqual(loaded["/p/s.jsonl"]?.first?.tokens, 100)
    }

    func test_projects_roundTrip() throws {
        let b = ProjectBreakdown(entries: [.init(displayName: "a", path: "/a", tokens: 5, cost: 0.5)])
        try store.writeProjects(b)
        XCTAssertEqual(try store.readProjects()?.entries.first?.tokens, 5)
    }
}
