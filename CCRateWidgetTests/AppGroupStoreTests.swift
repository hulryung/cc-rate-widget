import XCTest

final class AppGroupStoreTests: XCTestCase {
    var tmpDir: URL!
    var store: AppGroupStore!

    override func setUp() {
        super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AppGroupStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = AppGroupStore(containerURL: tmpDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    func test_writeAndRead_limits_roundTrip() throws {
        let original = InferredLimits(
            fiveHourTokens: 100_000,
            sevenDayTokens: 500_000,
            sevenDaySonnetTokens: 250_000,
            weeklyMaxObserved: 400_000,
            fiveHourMaxObserved: 90_000,
            manualPlanTier: .max5
        )
        try store.writeLimits(original)
        let loaded = try store.readLimits()
        XCTAssertEqual(loaded?.fiveHourTokens, 100_000)
        XCTAssertEqual(loaded?.manualPlanTier, .max5)
    }

    func test_read_missingFile_returnsNil() throws {
        XCTAssertNil(try store.readLimits())
    }

    func test_read_corruptFile_throws() throws {
        let url = tmpDir.appendingPathComponent("limits.json")
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.readLimits())
    }

    func test_offsets_roundTrip() throws {
        try store.writeOffsets(["/a.jsonl": 100, "/b.jsonl": 250])
        let loaded = try store.readOffsets()
        XCTAssertEqual(loaded, ["/a.jsonl": 100, "/b.jsonl": 250])
    }
}
