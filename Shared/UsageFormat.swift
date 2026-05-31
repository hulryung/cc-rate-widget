import Foundation

/// Compact human formatting for token counts and cost, shared by the app and widget.
enum UsageFormat {
    /// 2_400_000 → "2.4M", 240_000 → "240K", 950 → "950".
    static func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...:
            return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:
            return String(format: "%.0fK", Double(n) / 1_000)
        default:
            return "\(n)"
        }
    }

    /// 24.0 → "$24.00", 0.4 → "$0.40".
    static func cost(_ d: Double) -> String {
        String(format: "$%.2f", d)
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
