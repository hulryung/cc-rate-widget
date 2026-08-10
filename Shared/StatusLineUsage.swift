import Foundation

/// Anthropic's own rate-limit percentages, taken from the JSON Claude Code hands to its
/// status-line command on stdin.
///
/// This is the documented way to the same numbers `/status` prints, and it costs nothing:
/// no Keychain read, no network call, no token to hold. The figures arrived with a response
/// Claude Code had already made, and a one-line addition to the user's status-line script
/// drops them here.
///
/// It replaces reading Claude Code's Keychain item, which was never free. macOS gates that
/// item on an ACL *and* a partition list, and granting one program access narrows the list
/// against the other — so the app and Claude Code took turns being prompted, and "Always
/// Allow" could not settle it.
///
/// The trade is freshness. The file only advances while a Claude Code session is running,
/// so an old one describes a window that may since have rolled over. Past `staleAfter` it
/// is ignored rather than shown, because a stale percentage presented as current is a
/// worse failure than no percentage at all.
struct StatusLineUsage {
    struct Window {
        let utilization: Double      // 0…1, converted from Claude Code's 0…100
        let resetsAt: Date?
    }

    let fiveHour: Window?
    let sevenDay: Window?
    let writtenAt: Date

    static let fileName = "statusline-usage.json"
    static let staleAfter: TimeInterval = 60 * 60

    var isEmpty: Bool { fiveHour == nil && sevenDay == nil }

    /// Reads and validates the file, returning nil when it is missing, malformed, carries
    /// neither window, or is too old to describe now.
    static func read(from container: URL, now: Date = Date()) -> StatusLineUsage? {
        let url = container.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return parse(obj, now: now)
    }

    /// Pure parsing half, so the staleness and shape rules are testable without a file.
    static func parse(_ obj: [String: Any], now: Date) -> StatusLineUsage? {
        guard let stamp = (obj["written_at"] as? NSNumber)?.doubleValue else { return nil }
        let writtenAt = Date(timeIntervalSince1970: stamp)

        // A clock that jumped backwards, or a file from the future, is not evidence of
        // anything current. Treat both directions as stale.
        let age = now.timeIntervalSince(writtenAt)
        guard age >= -60, age <= staleAfter else { return nil }

        let limits = obj["rate_limits"] as? [String: Any] ?? [:]
        let out = StatusLineUsage(fiveHour: window(limits["five_hour"]),
                                  sevenDay: window(limits["seven_day"]),
                                  writtenAt: writtenAt)
        return out.isEmpty ? nil : out
    }

    /// Either window may be absent on its own — Claude Code documents that, and a session
    /// that has not yet had an API response carries neither.
    private static func window(_ raw: Any?) -> Window? {
        guard let d = raw as? [String: Any],
              let pct = (d["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
        let resets = (d["resets_at"] as? NSNumber)?.doubleValue
        return Window(utilization: pct / 100.0,
                      resetsAt: resets.map { Date(timeIntervalSince1970: $0) })
    }
}
