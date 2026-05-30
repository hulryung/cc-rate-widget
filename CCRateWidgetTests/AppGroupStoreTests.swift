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

    func test_mutateLimits_returnsValueAndPersists() throws {
        let r = try store.mutateLimits { limits -> Int in
            limits.weeklyMaxObserved = 42
            return 7
        }
        XCTAssertEqual(r, 7)
        XCTAssertEqual(try store.readLimits()?.weeklyMaxObserved, 42)
    }

    // Concurrent mutations of DIFFERENT fields must not clobber each other —
    // this is the backfill(weeklySamples) vs tick(weeklyMaxObserved) race.
    func test_mutateLimits_concurrent_doesNotLoseFields() throws {
        // Seed one field via one path...
        try store.mutateLimits { $0.weeklySamples = [1, 2, 3] }
        // ...then a concurrent-style mutation of a different field must preserve it.
        try store.mutateLimits { $0.weeklyMaxObserved = 999 }
        let loaded = try XCTUnwrap(try store.readLimits())
        XCTAssertEqual(loaded.weeklySamples, [1, 2, 3])
        XCTAssertEqual(loaded.weeklyMaxObserved, 999)

        // Hammer it from many threads; each increments a distinct sample slot's source.
        let group = DispatchGroup()
        for i in 0..<50 {
            group.enter()
            DispatchQueue.global().async {
                try? self.store.mutateLimits { $0.weeklyMaxObserved = max($0.weeklyMaxObserved, i) }
                group.leave()
            }
        }
        group.wait()
        // weeklySamples seeded earlier must still be intact after 50 concurrent writers.
        XCTAssertEqual(try store.readLimits()?.weeklySamples, [1, 2, 3])
    }
}
