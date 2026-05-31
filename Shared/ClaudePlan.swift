import Foundation

/// Reads the subscription plan from Claude Code's own credentials file
/// (`~/.claude/.credentials.json` → `claudeAiOauth.rateLimitTier`). This is a local
/// config field, not an API call — no token use, no ToS concern. Used only to label
/// the usage gauge ("Max 20x"); the percentage denominator is still self-calibrated,
/// because Anthropic doesn't publish per-tier token limits in our accounting unit.
enum ClaudePlan {
    /// Maps a `rateLimitTier` string (e.g. "default_claude_max_20x") to a friendly name.
    static func friendlyName(tier: String?) -> String? {
        guard let t = tier?.lowercased() else { return nil }
        if t.contains("max_20x") { return "Max 20x" }
        if t.contains("max_5x")  { return "Max 5x" }
        if t.contains("team")    { return "Team" }
        if t.contains("pro")     { return "Pro" }
        if t.contains("free")    { return "Free" }
        return nil
    }

    /// Reads the plan name from the credentials file. nil if absent/unreadable.
    static func detect(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let url = home.appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any] else { return nil }
        return friendlyName(tier: oauth["rateLimitTier"] as? String)
    }
}
