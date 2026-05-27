import XCTest

final class AlertStateRoundTripTests: XCTestCase {
    func test_alertState_roundTrip() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alerts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = AppGroupStore(containerURL: dir)
        let s = AlertState(lastThresholdFired: 0.80,
                           forecastFiredAt: Date().timeIntervalSince1970,
                           windowResetsAt: Date().timeIntervalSince1970 + 3600)
        try store.writeAlertState(s)
        let loaded = try XCTUnwrap(store.readAlertState())
        XCTAssertEqual(loaded.lastThresholdFired, 0.80)
    }

    func test_alertState_missingFile_returnsNil() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alerts-missing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AppGroupStore(containerURL: dir)
        XCTAssertNil(try store.readAlertState())
    }
}
