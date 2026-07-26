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

    // MARK: - Cache-creation TTL split

    /// Current Claude Code emits a `cache_creation` object splitting the write total
    /// between 1-hour and 5-minute entries, which are billed at different rates.
    func test_decode_splitsCacheCreationByTTL() throws {
        let line = #"{"type":"assistant","timestamp":"2026-07-22T01:54:53.430Z","cwd":"/p","requestId":"req_1","message":{"id":"msg_1","model":"claude-opus-4-8","usage":{"input_tokens":2,"output_tokens":482,"cache_creation_input_tokens":19499,"cache_read_input_tokens":20369,"cache_creation":{"ephemeral_1h_input_tokens":19499,"ephemeral_5m_input_tokens":0}}}}"#
        let evt = try XCTUnwrap(JSONLEvent.decode(line: line))
        XCTAssertEqual(evt.usage.cacheWrite1h, 19499)
        XCTAssertEqual(evt.usage.cacheWrite5m, 0)
        XCTAssertEqual(evt.usage.cacheWrite, 19499)
    }

    func test_decode_mixedTTL_splitsProportionally() throws {
        let line = #"{"type":"assistant","timestamp":"2026-07-22T01:54:53.430Z","cwd":"/p","message":{"model":"claude-opus-4-8","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":1000,"cache_creation":{"ephemeral_1h_input_tokens":600,"ephemeral_5m_input_tokens":400}}}}"#
        let evt = try XCTUnwrap(JSONLEvent.decode(line: line))
        XCTAssertEqual(evt.usage.cacheWrite1h, 600)
        XCTAssertEqual(evt.usage.cacheWrite5m, 400)
    }

    /// Older logs have no `cache_creation` object — the whole total stays on the
    /// cheaper 5-minute rate rather than being dropped.
    func test_decode_withoutBreakdown_treatsWritesAsFiveMinute() throws {
        let line = #"{"type":"assistant","timestamp":"2026-05-27T08:14:22.103Z","cwd":"/p","message":{"model":"claude-opus-4-7","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":1839}}}"#
        let evt = try XCTUnwrap(JSONLEvent.decode(line: line))
        XCTAssertEqual(evt.usage.cacheWrite5m, 1839)
        XCTAssertEqual(evt.usage.cacheWrite1h, 0)
    }

    /// A breakdown that disagrees with the billed total occurs in real logs. The total
    /// wins, so the split can never invent or drop billable tokens.
    func test_decode_inconsistentBreakdown_clampsToBilledTotal() throws {
        let line = #"{"type":"assistant","timestamp":"2026-07-22T01:54:53.430Z","cwd":"/p","message":{"model":"claude-opus-4-8","usage":{"cache_creation_input_tokens":500,"cache_creation":{"ephemeral_1h_input_tokens":900,"ephemeral_5m_input_tokens":300}}}}"#
        let evt = try XCTUnwrap(JSONLEvent.decode(line: line))
        XCTAssertEqual(evt.usage.cacheWrite, 500)
        XCTAssertEqual(evt.usage.cacheWrite1h, 500)
        XCTAssertEqual(evt.usage.cacheWrite5m, 0)
    }
}
