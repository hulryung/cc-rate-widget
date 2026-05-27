import XCTest

final class JSONLEventTests: XCTestCase {
    func test_decode_assistant_full() throws {
        let line = #"{"type":"assistant","timestamp":"2026-05-27T08:14:22.103Z","sessionId":"abc","cwd":"/Users/dk/dev/proj","message":{"model":"claude-opus-4-7","usage":{"input_tokens":412,"cache_creation_input_tokens":1839,"cache_read_input_tokens":27431,"output_tokens":286}}}"#
        let evt = try XCTUnwrap(JSONLEvent.decode(line: line))
        XCTAssertEqual(evt.cwd, "/Users/dk/dev/proj")
        XCTAssertEqual(evt.model, "claude-opus-4-7")
        XCTAssertEqual(evt.usage.input, 412)
        XCTAssertEqual(evt.usage.output, 286)
        XCTAssertEqual(evt.usage.cacheWrite, 1839)
        XCTAssertEqual(evt.usage.cacheRead, 27431)
    }

    func test_decode_userEvent_returnsNil() {
        let line = #"{"type":"user","timestamp":"2026-05-27T08:14:22.000Z","sessionId":"abc"}"#
        XCTAssertNil(JSONLEvent.decode(line: line))
    }

    func test_decode_corruptLine_returnsNil() {
        XCTAssertNil(JSONLEvent.decode(line: "not a json line"))
    }

    func test_decode_assistant_missingCacheFields_defaultsToZero() throws {
        let line = #"{"type":"assistant","timestamp":"2026-05-27T08:14:22.000Z","sessionId":"abc","cwd":"/p","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20}}}"#
        let evt = try XCTUnwrap(JSONLEvent.decode(line: line))
        XCTAssertEqual(evt.usage.cacheWrite, 0)
        XCTAssertEqual(evt.usage.cacheRead, 0)
    }
}
