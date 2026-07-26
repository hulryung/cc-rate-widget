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
        let writes = cacheWrites(usage)
        let u = TokenUsage(
            input:        (usage["input_tokens"] as? Int) ?? 0,
            output:       (usage["output_tokens"] as? Int) ?? 0,
            cacheWrite5m: writes.fiveMinute,
            cacheWrite1h: writes.oneHour,
            cacheRead:    (usage["cache_read_input_tokens"] as? Int) ?? 0
        )
        let messageID = msg["id"] as? String
        let requestID = (raw["requestId"] as? String) ?? (raw["request_id"] as? String)
        let key = messageID.map { "\($0):\(requestID ?? "")" }
        return JSONLEvent(timestamp: date, cwd: cwd, model: model, usage: u, dedupeKey: key)
    }

    /// Splits cache-creation tokens by TTL. `cache_creation_input_tokens` is the total
    /// Anthropic bills on; the `cache_creation` object only says how that total divides
    /// between the 1-hour and 5-minute buckets (they're priced 2x and 1.25x input).
    /// The total stays authoritative — the split is clamped to it, so a missing or
    /// inconsistent breakdown can never invent or drop billable tokens.
    private static func cacheWrites(_ usage: [String: Any]) -> (fiveMinute: Int, oneHour: Int) {
        let total = max(0, (usage["cache_creation_input_tokens"] as? Int) ?? 0)
        let breakdown = usage["cache_creation"] as? [String: Any]
        let reported1h = max(0, (breakdown?["ephemeral_1h_input_tokens"] as? Int) ?? 0)
        let oneHour = min(reported1h, total)
        return (fiveMinute: total - oneHour, oneHour: oneHour)
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
