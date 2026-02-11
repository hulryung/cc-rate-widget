import Foundation

final class RateFetcher {
    static let shared = RateFetcher()
    private let endpoint = "https://api.anthropic.com/api/oauth/usage"

    private init() {}

    func fetchRateData() async -> RateData {
        guard let token = await CredentialManager.shared.refreshTokenIfNeeded() else {
            return errorData()
        }

        guard let url = URL(string: endpoint) else {
            return errorData()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return errorData()
            }

            guard httpResponse.statusCode == 200 else {
                return errorData()
            }

            let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
            return mapResponse(usage)
        } catch {
            return errorData()
        }
    }

    private func mapResponse(_ usage: UsageResponse) -> RateData {
        let session = CategoryData(
            utilization: usage.fiveHour.utilization / 100.0,
            resetsAt: parseISO(usage.fiveHour.resetsAt)
        )
        let weekly = CategoryData(
            utilization: usage.sevenDay.utilization / 100.0,
            resetsAt: parseISO(usage.sevenDay.resetsAt)
        )
        let weeklySonnet = CategoryData(
            utilization: usage.sevenDaySonnet.utilization / 100.0,
            resetsAt: parseISO(usage.sevenDaySonnet.resetsAt)
        )
        let overage = OverageData(
            isEnabled: usage.extraUsage.isEnabled,
            utilization: usage.extraUsage.utilization / 100.0,
            spent: (usage.extraUsage.usedCredits ?? 0) / 100.0,
            limit: (usage.extraUsage.monthlyLimit ?? 0) / 100.0
        )

        let maxUtil = max(usage.fiveHour.utilization, usage.sevenDay.utilization)
        let status: OverallStatus
        if maxUtil >= 100 {
            status = .rateLimited
        } else if maxUtil >= 80 {
            status = .warning
        } else {
            status = .active
        }

        return RateData(
            session: session,
            weekly: weekly,
            weeklySonnet: weeklySonnet,
            overage: overage,
            fetchedAt: Date(),
            status: status
        )
    }

    private func parseISO(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private func errorData() -> RateData {
        RateData(
            session: CategoryData(utilization: 0, resetsAt: nil),
            weekly: CategoryData(utilization: 0, resetsAt: nil),
            weeklySonnet: CategoryData(utilization: 0, resetsAt: nil),
            overage: OverageData(isEnabled: false, utilization: 0, spent: 0, limit: 0),
            fetchedAt: Date(),
            status: .error
        )
    }
}
