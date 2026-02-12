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
    let utilization: Double
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

    static let placeholder = RateData(
        session: CategoryData(utilization: 0.35, resetsAt: Date().addingTimeInterval(3600)),
        weekly: CategoryData(utilization: 0.52, resetsAt: Date().addingTimeInterval(86400)),
        weeklySonnet: CategoryData(utilization: 0.28, resetsAt: Date().addingTimeInterval(86400)),
        overage: OverageData(isEnabled: false, utilization: 0, spent: 0, limit: 0),
        fetchedAt: Date(),
        status: .active
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
    case error
    case unknown

    var label: String {
        switch self {
        case .active: return "Active"
        case .warning: return "Warning"
        case .rateLimited: return "Rate Limited"
        case .unauthorized: return "Session Expired"
        case .error: return "Error"
        case .unknown: return "Unknown"
        }
    }
}
