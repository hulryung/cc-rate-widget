import Foundation
import Security

/// Anthropic's official rate-limit utilization, the same numbers Claude Code's `/status`
/// shows. Obtained by reading Claude Code's own (keychain-stored, auto-refreshed) OAuth
/// token and querying the usage endpoint. We never refresh the token ourselves —
/// refreshing could rotate Claude Code's refresh token and break its login.
struct OfficialUsage: Equatable {
    let fiveHour: Double         // 0…1
    let sevenDay: Double
    let sevenDaySonnet: Double
    let fiveHourResetsAt: Date?
    let sevenDayResetsAt: Date?

    private static let endpoint = "https://api.anthropic.com/api/oauth/usage"

    /// Synchronous (safe to call from the aggregator's background queue). Returns nil on any
    /// failure: OAuth disabled, no/expired keychain token, access denied, or non-200.
    static func fetch() -> OfficialUsage? {
        guard let token = freshAccessToken(),
              let url = URL(string: endpoint) else { return nil }

        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var out: OfficialUsage?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200, let data else {
                if let http = resp as? HTTPURLResponse {
                    NSLog("[OfficialUsage] HTTP \(http.statusCode)")
                }
                return
            }
            out = parse(data)
        }.resume()
        _ = sem.wait(timeout: .now() + 12)
        return out
    }

    /// Pure parse of the usage JSON. Exposed for testing.
    static func parse(_ data: Data) -> OfficialUsage? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard o["five_hour"] != nil || o["seven_day"] != nil else { return nil }
        func util(_ key: String) -> Double {
            guard let v = (o[key] as? [String: Any])?["utilization"] as? Double else { return 0 }
            return v / 100.0
        }
        func reset(_ key: String) -> Date? {
            guard let s = (o[key] as? [String: Any])?["resets_at"] as? String else { return nil }
            return iso.date(from: s) ?? isoNoFrac.date(from: s)
        }
        return OfficialUsage(
            fiveHour: util("five_hour"),
            sevenDay: util("seven_day"),
            sevenDaySonnet: util("seven_day_sonnet"),
            fiveHourResetsAt: reset("five_hour"),
            sevenDayResetsAt: reset("seven_day")
        )
    }

    /// Reads Claude Code's keychain credentials and returns the access token only if it's
    /// still valid. Returns nil (no refresh) when missing/expired/denied.
    ///
    /// Also hands the subscription tier to `ClaudePlan`. Claude Code no longer writes
    /// `~/.claude/.credentials.json`, so the Keychain is the only remaining source for the
    /// plan label — and this is the one place already paying for a Keychain read, so
    /// piggybacking here avoids adding a second macOS permission prompt.
    private static func freshAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }

        // The tier stays meaningful even when the token itself has expired.
        ClaudePlan.remember(tier: oauth["rateLimitTier"] as? String)

        if let expiresMs = oauth["expiresAt"] as? Double,
           Date().timeIntervalSince1970 * 1000 >= expiresMs { return nil }   // expired → fall back
        return token
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
}
