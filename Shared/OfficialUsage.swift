import Foundation
import Security

/// One rate-limit window as Anthropic reports it.
///
/// The set is not fixed. Alongside the session and all-model weekly windows, the API
/// returns zero or more *scoped* windows — a per-model-family limit such as "Fable" —
/// and which ones appear varies by account and over time. `/status` renders exactly the
/// windows present here, so the app does too rather than hardcoding a list.
struct OfficialLimit: Equatable, Identifiable {
    /// "session", "weekly_all", "weekly_scoped", or something newer.
    let kind: String
    /// Model family for a scoped window ("Fable"); nil when the window covers everything.
    let scopeLabel: String?
    let utilization: Double      // 0…1
    let resetsAt: Date?
    /// Anthropic's own assessment — "normal", and louder values we pass through untouched.
    let severity: String?

    var id: String { scopeLabel.map { "\(kind):\($0)" } ?? kind }

    /// "Weekly · Fable", "Weekly", "Session".
    var title: String {
        let base: String
        switch kind {
        case "session":                     base = "Session"
        case "weekly_all", "weekly_scoped": base = "Weekly"
        default:                            base = kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return scopeLabel.map { "\(base) · \($0)" } ?? base
    }

    var subtitle: String {
        kind == "session" ? "5 hours" : "7 days"
    }
}

/// Anthropic's official rate-limit utilization — the same numbers Claude Code's `/status`
/// shows. Obtained by reading Claude Code's own (keychain-stored, auto-refreshed) OAuth
/// token and querying the usage endpoint. We never refresh the token ourselves —
/// refreshing could rotate Claude Code's refresh token and break its login.
struct OfficialUsage: Equatable {
    let limits: [OfficialLimit]

    private static let endpoint = "https://api.anthropic.com/api/oauth/usage"

    /// The all-model weekly window, used for the menu-bar percentage.
    var weekly: OfficialLimit? {
        limits.first { $0.kind == "weekly_all" } ?? limits.first { $0.kind.hasPrefix("weekly") }
    }
    var session: OfficialLimit? { limits.first { $0.kind == "session" } }

    /// Synchronous (safe to call from the aggregator's background queue). Returns nil on any
    /// failure: OAuth disabled, no/expired keychain token, access denied, or non-200.
    static func fetch() -> OfficialUsage? {
        guard let token = accessToken() else { return nil }
        switch request(with: token) {
        case .success(let usage):
            return usage
        case .unauthorized:
            // Claude Code rotates its own token; ours went stale. This is the only case
            // worth paying a second keychain read for.
            clearCachedToken()
            guard let fresh = accessToken() else { return nil }
            if case .success(let usage) = request(with: fresh) { return usage }
            return nil
        case .failed:
            return nil
        }
    }

    private enum Outcome { case success(OfficialUsage), unauthorized, failed }

    private static func request(with token: String) -> Outcome {
        guard let url = URL(string: endpoint) else { return .failed }

        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var out = Outcome.failed
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            guard let http = resp as? HTTPURLResponse else { return }
            guard http.statusCode == 200, let data else {
                NSLog("[OfficialUsage] HTTP \(http.statusCode)")
                if http.statusCode == 401 || http.statusCode == 403 { out = .unauthorized }
                return
            }
            out = parse(data).map(Outcome.success) ?? .failed
        }.resume()
        _ = sem.wait(timeout: .now() + 12)
        return out
    }

    // MARK: - Token cache

    /// Reading the Keychain is what raises the macOS permission prompt, so it must happen
    /// as rarely as the token's own lifetime allows — not on every poll.
    ///
    /// This used to be read on every official-usage refresh. With a 15-minute refresh and
    /// an app that stays resident, that was ~96 Keychain reads a day, and any of them can
    /// prompt. The token is valid for hours, so hold it in memory for the process and go
    /// back to the Keychain only when it expires or the server rejects it.
    private static let tokenLock = NSLock()
    nonisolated(unsafe) private static var cachedToken: (value: String, expiresAt: Date?)?

    private static func accessToken() -> String? {
        tokenLock.lock()
        defer { tokenLock.unlock() }

        if let cached = cachedToken {
            let stillValid = cached.expiresAt.map { $0 > Date().addingTimeInterval(60) } ?? true
            if stillValid { return cached.value }
        }
        guard let read = readKeychain() else { return nil }
        cachedToken = read
        return read.value
    }

    private static func clearCachedToken() {
        tokenLock.lock()
        cachedToken = nil
        tokenLock.unlock()
    }

    /// Pure parse of the usage JSON. Exposed for testing.
    static func parse(_ data: Data) -> OfficialUsage? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // Preferred: the self-describing `limits` array, which is what `/status` renders
        // and the only place scoped per-model windows appear.
        if let raw = o["limits"] as? [[String: Any]] {
            let parsed = raw.compactMap(limit(from:))
            if !parsed.isEmpty { return OfficialUsage(limits: parsed) }
        }

        // Fallback for older responses that only had flat per-window objects. Kept because
        // the array is undocumented and could vanish as easily as it appeared.
        let legacy: [(String, String?)] = [
            ("five_hour", nil), ("seven_day", nil),
            ("seven_day_opus", "Opus"), ("seven_day_sonnet", "Sonnet"),
        ]
        var out: [OfficialLimit] = []
        for (key, scope) in legacy {
            guard let obj = o[key] as? [String: Any],
                  let util = obj["utilization"] as? Double else { continue }
            out.append(OfficialLimit(
                kind: key == "five_hour" ? "session" : (scope == nil ? "weekly_all" : "weekly_scoped"),
                scopeLabel: scope,
                utilization: util / 100.0,
                resetsAt: (obj["resets_at"] as? String).flatMap(date(from:)),
                severity: nil))
        }
        return out.isEmpty ? nil : OfficialUsage(limits: out)
    }

    private static func limit(from raw: [String: Any]) -> OfficialLimit? {
        guard let kind = raw["kind"] as? String else { return nil }
        // `percent` arrives as a whole number, but don't assume the encoding.
        guard let percent = (raw["percent"] as? NSNumber)?.doubleValue else { return nil }
        let scopeLabel = ((raw["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
        return OfficialLimit(
            kind: kind,
            scopeLabel: scopeLabel,
            utilization: percent / 100.0,
            resetsAt: (raw["resets_at"] as? String).flatMap(date(from:)),
            severity: raw["severity"] as? String)
    }

    /// Reads Claude Code's keychain credentials and returns the access token only if it's
    /// still valid. Returns nil (no refresh) when missing/expired/denied.
    ///
    /// Also hands the subscription tier to `ClaudePlan`. Claude Code no longer writes
    /// `~/.claude/.credentials.json`, so the Keychain is the only remaining source for the
    /// plan label — and this is the one place already paying for a Keychain read, so
    /// piggybacking here avoids adding a second macOS permission prompt.
    private static func readKeychain() -> (value: String, expiresAt: Date?)? {
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

        let expiresAt = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        if let expiresAt, expiresAt <= Date() { return nil }   // expired → fall back to local
        return (token, expiresAt)
    }

    private static func date(from s: String) -> Date? {
        iso.date(from: s) ?? isoNoFrac.date(from: s)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
}
