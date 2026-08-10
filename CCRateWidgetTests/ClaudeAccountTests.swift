import XCTest

final class ClaudeAccountTests: XCTestCase {
    private func data(_ obj: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: obj)
    }

    func test_readsTheSignedInAddress() {
        let d = data(["userID": "abc",
                      "oauthAccount": ["emailAddress": "someone@example.com",
                                       "organizationUuid": "715c576f"]])
        XCTAssertEqual(ClaudeAccount.parse(d), "someone@example.com")
    }

    func test_neverSignedIn_isNil() {
        XCTAssertNil(ClaudeAccount.parse(data(["userID": "abc"])))
    }

    func test_emptyAddress_isNil() {
        XCTAssertNil(ClaudeAccount.parse(data(["oauthAccount": ["emailAddress": ""]])),
                     "an empty string would render as a stray separator in the footer")
    }

    func test_garbage_isNil() {
        XCTAssertNil(ClaudeAccount.parse(Data("not json".utf8)))
        XCTAssertNil(ClaudeAccount.parse(data(["oauthAccount": "a string, not an object"])))
    }

    /// The file is over 100 KB and rewritten constantly, so a miss must be cheap and safe.
    func test_missingFile_isNil() {
        let nowhere = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        XCTAssertNil(ClaudeAccount.email(at: nowhere))
    }
}
