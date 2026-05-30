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
}
