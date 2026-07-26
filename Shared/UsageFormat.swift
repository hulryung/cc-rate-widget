import Foundation

/// Compact human formatting for token counts and cost, shared by the app and widget.
enum UsageFormat {
    /// 2_400_000 → "2.4M", 240_000 → "240K", 1_400 → "1.4K", 950 → "950".
    ///
    /// Two significant-ish digits throughout. A single "%.0fK" rule across the whole
    /// thousands range rendered 1,400 as "1K" — a 29% error on a headline number — and
    /// 999,900 as "1000K" rather than rolling over to "1.0M".
    static func tokens(_ n: Int) -> String {
        // Boundaries sit where the *rendered* value would roll over, not at the round
        // number — otherwise 99,999 prints "100.0K" and 999,900 prints "1000K".
        switch n {
        case 999_500...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 99_950...:  return String(format: "%.0fK", Double(n) / 1_000)   // 240K
        case 1_000...:   return String(format: "%.1fK", Double(n) / 1_000)   // 1.4K
        default:         return "\(n)"
        }
    }

    /// 24.0 → "$24.00", 0.4 → "$0.40", 2_427.67 → "$2,428".
    ///
    /// Grouping separators come from the locale; the currency stays USD because
    /// `Pricing` computes dollars — localizing the symbol would misstate the figure.
    /// Cents are dropped above $100, where they are noise.
    static func cost(_ d: Double) -> String {
        d.formatted(.currency(code: "USD").precision(.fractionLength(d >= 100 ? 0 : 2)))
    }

    /// 47 → "47m", 190 → "3h 10m".
    static func duration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    /// Reset moment with weekday, date and hour — no minutes. e.g. "Tue, Jun 3, 1 PM".
    static func resetMoment(_ date: Date) -> String {
        resetFormatter.string(from: date)
    }

    /// Coarse time remaining in days + hours only (no minutes/seconds). e.g. "2d 4h", "18h".
    static func remainingCoarse(until date: Date, from now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "now" }
        let totalHours = Int(seconds / 3600)        // floor to whole hours
        let days = totalHours / 24
        let hours = totalHours % 24
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if totalHours > 0 { return "\(totalHours)h" }
        return "<1h"
    }

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE MMM d h a")  // localized weekday/date/hour, no minutes
        return f
    }()
}
