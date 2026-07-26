import Foundation

/// The subscription plan name shown next to the usage gauge ("Max 20x").
///
/// Claude Code used to write this to `~/.claude/.credentials.json`; current versions keep
/// credentials in the login Keychain and no longer create that file, which left the label
/// permanently blank. We deliberately do not read the Keychain from here: that triggers a
/// macOS permission prompt, and paying that for a cosmetic label would undo the throttling
/// added for the official-usage path. Instead the official-usage path — which reads the
/// Keychain anyway — hands the tier over via `remember(tier:)`, and we cache it.
///
/// The percentage denominator is still self-calibrated; this is only a label.
enum ClaudePlan {
    private static let cachedTierKey = "claudeRateLimitTier"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupStore.appGroupID)
    }

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

    /// Plan name from the credentials file if Claude Code still writes one, otherwise the
    /// tier last observed by the official-usage path. nil when neither is available.
    static func detect(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                       defaults: UserDefaults? = ClaudePlan.sharedDefaults) -> String? {
        if let tier = tierFromCredentialsFile(home: home) {
            return friendlyName(tier: tier)
        }
        return friendlyName(tier: defaults?.string(forKey: cachedTierKey))
    }

    /// Records a tier observed during a Keychain read the app was already performing.
    /// Ignores nil/empty so a failed read never clears a previously good value.
    static func remember(tier: String?, defaults: UserDefaults? = ClaudePlan.sharedDefaults) {
        guard let tier, !tier.isEmpty else { return }
        defaults?.set(tier, forKey: cachedTierKey)
    }

    /// Legacy location, still supported for older Claude Code installs.
    private static func tierFromCredentialsFile(home: URL) -> String? {
        let url = home.appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any] else { return nil }
        return oauth["rateLimitTier"] as? String
    }
}
