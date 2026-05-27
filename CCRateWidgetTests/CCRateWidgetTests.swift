import XCTest

final class SanityTests: XCTestCase {
    func test_sanity_arithmetic() {
        XCTAssertEqual(1 + 1, 2)
    }

    func test_sanity_sharedTypesVisible() {
        // Proves Shared/ sources are compiled into the test bundle's own module,
        // so future tests can reference Shared types without `@testable import`.
        let placeholder = RateData.placeholder
        XCTAssertEqual(placeholder.status, .active)
    }
}
