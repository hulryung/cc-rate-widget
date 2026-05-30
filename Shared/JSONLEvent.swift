import Foundation

struct JSONLEvent {
    let timestamp: Date
    let cwd: String
    let model: String
    let usage: TokenUsage
    /// Stable identity for de-duplication. Claude Code logs the same assistant turn in
    /// multiple files (session, sidechain, summary); counting every line double-counts.
    /// Matches ccusage's `messageId:requestId` key. nil when no message id is present
    /// (such events can't be deduped and are always counted).
    let dedupeKey: String?

    static func decode(line: String) -> JSONLEvent? {
        guard let data = line.data(using: .utf8) else { return nil }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard (raw["type"] as? String) == "assistant" else { return nil }
        guard let ts = raw["timestamp"] as? String,
              let date = parseTimestamp(ts) else { return nil }
        guard let cwd = raw["cwd"] as? String else { return nil }
        guard let msg = raw["message"] as? [String: Any],
              let model = msg["model"] as? String,
              let usage = msg["usage"] as? [String: Any] else { return nil }
        let u = TokenUsage(
            input:      (usage["input_tokens"] as? Int) ?? 0,
            output:     (usage["output_tokens"] as? Int) ?? 0,
            cacheWrite: (usage["cache_creation_input_tokens"] as? Int) ?? 0,
            cacheRead:  (usage["cache_read_input_tokens"] as? Int) ?? 0
        )
        let messageID = msg["id"] as? String
        let requestID = (raw["requestId"] as? String) ?? (raw["request_id"] as? String)
        let key = messageID.map { "\($0):\(requestID ?? "")" }
        return JSONLEvent(timestamp: date, cwd: cwd, model: model, usage: u, dedupeKey: key)
    }

    private static let isoWithFractions: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoWithoutFractions: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseTimestamp(_ s: String) -> Date? {
        if let d = isoWithFractions.date(from: s) { return d }
        return isoWithoutFractions.date(from: s)
    }
}
