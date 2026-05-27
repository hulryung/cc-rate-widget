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

struct RateData {
    let session: CategoryData       // five_hour
    let weekly: CategoryData        // seven_day
    let weeklySonnet: CategoryData  // seven_day_sonnet
    let overage: OverageData        // extra_usage
    let fetchedAt: Date
    let status: OverallStatus
    let source: RateDataSource

    static let placeholder = RateData(
        session: CategoryData(utilization: 0.35, resetsAt: Date().addingTimeInterval(3600)),
        weekly: CategoryData(utilization: 0.52, resetsAt: Date().addingTimeInterval(86400)),
        weeklySonnet: CategoryData(utilization: 0.28, resetsAt: Date().addingTimeInterval(86400)),
        overage: OverageData(isEnabled: false, utilization: 0, spent: 0, limit: 0),
        fetchedAt: Date(),
        status: .active,
        source: .jsonl
    )
}

struct CategoryData {
    let utilization: Double  // 0.0 to 1.0
    let resetsAt: Date?
}

struct OverageData {
    let isEnabled: Bool
    let utilization: Double  // 0.0 to 1.0
    let spent: Double        // dollars
    let limit: Double        // dollars
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

// MARK: - Inferred Limits

struct InferredLimits: Codable {
    /// nil when we don't yet have a confident estimate (learning state).
    var fiveHourTokens: Int? = nil
    var sevenDayTokens: Int? = nil
    var sevenDaySonnetTokens: Int? = nil

    /// Highest 7d-window total ever observed (for rolling 1.05× ratchet).
    var weeklyMaxObserved: Int = 0
    var fiveHourMaxObserved: Int = 0

    /// Optional cached values pulled from OAuth (when enabled).
    var officialFiveHourTokens: Int? = nil
    var officialSevenDayTokens: Int? = nil

    var weeklySamples: [Int] = []
    var fiveHourSamples: [Int] = []

    /// Manual user override; when non-nil, beats both P90 and official.
    var manualPlanTier: ManualPlanTier? = nil

    enum ManualPlanTier: String, Codable {
        case pro
        case max5
        case max20
    }

    init(
        fiveHourTokens: Int? = nil,
        sevenDayTokens: Int? = nil,
        sevenDaySonnetTokens: Int? = nil,
        weeklyMaxObserved: Int = 0,
        fiveHourMaxObserved: Int = 0,
        officialFiveHourTokens: Int? = nil,
        officialSevenDayTokens: Int? = nil,
        weeklySamples: [Int] = [],
        fiveHourSamples: [Int] = [],
        manualPlanTier: ManualPlanTier? = nil
    ) {
        self.fiveHourTokens = fiveHourTokens
        self.sevenDayTokens = sevenDayTokens
        self.sevenDaySonnetTokens = sevenDaySonnetTokens
        self.weeklyMaxObserved = weeklyMaxObserved
        self.fiveHourMaxObserved = fiveHourMaxObserved
        self.officialFiveHourTokens = officialFiveHourTokens
        self.officialSevenDayTokens = officialSevenDayTokens
        self.weeklySamples = weeklySamples
        self.fiveHourSamples = fiveHourSamples
        self.manualPlanTier = manualPlanTier
    }

    private enum CodingKeys: String, CodingKey {
        case fiveHourTokens, sevenDayTokens, sevenDaySonnetTokens
        case weeklyMaxObserved, fiveHourMaxObserved
        case officialFiveHourTokens, officialSevenDayTokens
        case weeklySamples, fiveHourSamples
        case manualPlanTier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.fiveHourTokens         = try c.decodeIfPresent(Int.self, forKey: .fiveHourTokens)
        self.sevenDayTokens         = try c.decodeIfPresent(Int.self, forKey: .sevenDayTokens)
        self.sevenDaySonnetTokens   = try c.decodeIfPresent(Int.self, forKey: .sevenDaySonnetTokens)
        self.weeklyMaxObserved      = try c.decodeIfPresent(Int.self, forKey: .weeklyMaxObserved) ?? 0
        self.fiveHourMaxObserved    = try c.decodeIfPresent(Int.self, forKey: .fiveHourMaxObserved) ?? 0
        self.officialFiveHourTokens = try c.decodeIfPresent(Int.self, forKey: .officialFiveHourTokens)
        self.officialSevenDayTokens = try c.decodeIfPresent(Int.self, forKey: .officialSevenDayTokens)
        self.weeklySamples          = try c.decodeIfPresent([Int].self, forKey: .weeklySamples) ?? []
        self.fiveHourSamples        = try c.decodeIfPresent([Int].self, forKey: .fiveHourSamples) ?? []
        self.manualPlanTier         = try c.decodeIfPresent(ManualPlanTier.self, forKey: .manualPlanTier)
    }
}
