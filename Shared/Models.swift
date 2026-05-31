import Foundation

// MARK: - API Response Models

struct UsageResponse: Codable {
    let fiveHour: RateCategory
    let sevenDay: RateCategory
    let sevenDaySonnet: RateCategory
    let extraUsage: ExtraUsage

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }
}

struct RateCategory: Codable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct ExtraUsage: Codable {
    let isEnabled: Bool
    let utilization: Double?
    let usedCredits: Double?
    let monthlyLimit: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case utilization
        case usedCredits = "used_credits"
        case monthlyLimit = "monthly_limit"
    }
}

// MARK: - Widget Data Model

/// What the `limitTokens` denominator represents — so the UI can label the percentage
/// honestly. JSONL can't give Anthropic's official quota %, so a percentage is always
/// either against a user-entered cap or against the user's own observed peak.
enum LimitKind: String {
    case userLimit     // user typed a token cap in Settings
    case typicalPeak   // P90 of the user's own historical 5-hour blocks (self-calibrated)
    case official      // Anthropic's real utilization (matches Claude Code /status)
}

/// Absolute usage for one rolling window. JSONL gives accurate token counts and cost.
struct CategoryData {
    let tokens: Int
    let cost: Double          // USD
    let resetsAt: Date?       // window reset time
    var limitTokens: Int?     // token-based denominator; nil = none
    var limitKind: LimitKind?
    var officialUtilization: Double?   // when set, this IS the percentage (from Anthropic)

    init(tokens: Int, cost: Double, resetsAt: Date?,
         limitTokens: Int? = nil, limitKind: LimitKind? = nil, officialUtilization: Double? = nil) {
        self.tokens = tokens
        self.cost = cost
        self.resetsAt = resetsAt
        self.limitTokens = limitTokens
        self.limitKind = limitKind
        self.officialUtilization = officialUtilization
    }

    /// Official % wins; otherwise tokens / token-limit; otherwise nil.
    var utilization: Double? {
        if let officialUtilization { return officialUtilization }
        guard let limitTokens, limitTokens > 0 else { return nil }
        return Double(tokens) / Double(limitTokens)
    }

    /// Overlay Anthropic's official utilization, keeping the locally-measured tokens/cost.
    func withOfficial(_ util: Double, resetsAt: Date?) -> CategoryData {
        CategoryData(tokens: tokens, cost: cost, resetsAt: resetsAt ?? self.resetsAt,
                     limitTokens: nil, limitKind: .official, officialUtilization: util)
    }
}

struct RateData {
    let session: CategoryData       // five_hour
    let weekly: CategoryData        // seven_day
    let weeklySonnet: CategoryData  // seven_day_sonnet
    let fetchedAt: Date
    let status: OverallStatus
    let source: RateDataSource
    var burnTokensPerSecond: Double = 0   // last 30 min, for time-to-limit projection
    var planName: String? = nil           // detected from Claude Code credentials (e.g. "Max 20x")
    var officialFetchedAt: Date? = nil    // when the official % was last read (to throttle keychain reads)

    static let placeholder = RateData(
        session: CategoryData(tokens: 240_000, cost: 1.20, resetsAt: Date().addingTimeInterval(3600), limitTokens: 1_000_000, limitKind: .typicalPeak),
        weekly: CategoryData(tokens: 3_800_000, cost: 24.00, resetsAt: Date().addingTimeInterval(86400), limitTokens: 10_000_000, limitKind: .userLimit),
        weeklySonnet: CategoryData(tokens: 120_000, cost: 0.40, resetsAt: Date().addingTimeInterval(86400)),
        fetchedAt: Date(),
        status: .active,
        source: .jsonl,
        burnTokensPerSecond: 1800,
        planName: "Max 20x"
    )
}

enum OverallStatus: String {
    case active
    case warning
    case rateLimited = "rate_limited"
    case unauthorized
    case forbidden
    case notLoggedIn = "not_logged_in"
    case error
    case unknown
    case noLocalData = "no_local_data"

    var label: String {
        switch self {
        case .active: return "Active"
        case .warning: return "Warning"
        case .rateLimited: return "Rate Limited"
        case .unauthorized: return "Session Expired"
        case .forbidden: return "Access Blocked"
        case .notLoggedIn: return "Not Logged In"
        case .error: return "Error"
        case .unknown: return "Unknown"
        case .noLocalData: return "No Local Data"
        }
    }
}

// MARK: - Data Source

enum RateDataSource: String, Codable {
    case jsonl
    case oauth
    case hybrid
    case partial            // backfill in progress
    case noLocalData = "no_local_data"
}

// MARK: - Project Breakdown

struct ProjectBreakdown: Codable {
    struct Entry: Codable, Identifiable, Equatable {
        var id: String { path }
        let displayName: String
        let path: String          // raw cwd
        let tokens: Int
        let cost: Double          // USD
    }

    let entries: [Entry]
    var aliases: [String: String] = [:]   // cwd → user-chosen display name

    func topN(_ n: Int) -> [Entry] {
        entries.sorted(by: { $0.tokens > $1.tokens }).prefix(n).map { $0 }
    }

    init(entries: [Entry], aliases: [String: String] = [:]) {
        self.entries = entries
        self.aliases = aliases
    }

    private enum CodingKeys: String, CodingKey { case entries, aliases }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.entries = try c.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        self.aliases = try c.decodeIfPresent([String: String].self, forKey: .aliases) ?? [:]
    }
}

