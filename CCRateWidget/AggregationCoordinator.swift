import Foundation
import WidgetKit

@MainActor
final class AggregationCoordinator: ObservableObject {
    static let shared = AggregationCoordinator()

    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()
    private var timer: Timer?
    private let intervalSeconds: TimeInterval = 5 * 60

    @Published var lastSnapshot: RateData?
    @Published var lastError: String?

    private init() {}

    func start() {
        runOnce()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runOnce() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func runOnce() {
        queue.addOperation { [weak self] in
            guard let self else { return }
            do {
                let rate = try self.tick()
                Task { @MainActor in
                    self.lastSnapshot = rate
                    self.lastError = nil
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } catch {
                NSLog("[Coordinator] tick failed: \(error)")
                Task { @MainActor in self.lastError = "\(error)" }
            }
        }
    }

    private nonisolated func tick() throws -> RateData {
        let store = AppGroupStore.shared
        let root  = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)

        guard FileManager.default.fileExists(atPath: root.path) else {
            let r = RateData(
                session:      CategoryData(utilization: 0, resetsAt: nil),
                weekly:       CategoryData(utilization: 0, resetsAt: nil),
                weeklySonnet: CategoryData(utilization: 0, resetsAt: nil),
                overage:      OverageData(isEnabled: false, utilization: 0, spent: 0, limit: 0),
                fetchedAt: Date(),
                status: .noLocalData,
                source: .noLocalData
            )
            try store.writeRate(r)
            return r
        }

        Backfill.runIfNeeded(rootDir: root, store: store)

        let aggregator = JSONLAggregator(rootDir: root, store: store)
        let snap = try aggregator.aggregate(now: Date())
        var limits = (try store.readLimits()) ?? InferredLimits(weeklyMaxObserved: 0,
                                                                fiveHourMaxObserved: 0)
        let inferred = LimitInferrer.infer(
            currentSnapshot: snap,
            weeklySamples: limits.weeklySamples,
            fiveHourSamples: limits.fiveHourSamples,
            limits: &limits
        )
        try store.writeLimits(limits)
        try store.writeProjects(snap.projects)

        let now = Date()
        func cat(tokens: Int, limit: Int?, earliest: Date?, window: TimeInterval) -> CategoryData {
            let utilization: Double
            if let limit, limit > 0 {
                utilization = Double(tokens) / Double(limit)
            } else {
                utilization = 0
            }
            let resetsAt = earliest.map { $0.addingTimeInterval(window) }
            return CategoryData(utilization: utilization, resetsAt: resetsAt)
        }

        let session  = cat(tokens: snap.fiveHourTokens, limit: inferred.fiveHourTokens,
                           earliest: snap.earliestInFiveHour, window: 5 * 3600)
        let weekly   = cat(tokens: snap.sevenDayTokens, limit: inferred.sevenDayTokens,
                           earliest: snap.earliestInSevenDay, window: 7 * 86400)
        let sonnet   = cat(tokens: snap.sevenDaySonnetTokens, limit: inferred.sevenDaySonnetTokens,
                           earliest: snap.earliestInSevenDay, window: 7 * 86400)

        let maxUtil = max(session.utilization, weekly.utilization)
        let status: OverallStatus = maxUtil >= 1.0 ? .rateLimited
                                    : maxUtil >= 0.80 ? .warning
                                    : .active

        let source: RateDataSource = (inferred.sevenDayTokens == nil) ? .partial : .jsonl
        let rate = RateData(
            session: session,
            weekly: weekly,
            weeklySonnet: sonnet,
            overage: OverageData(isEnabled: false, utilization: 0, spent: 0, limit: 0),
            fetchedAt: now,
            status: status,
            source: source
        )

        try store.writeRate(rate)

        // Alert pass.
        let storedAlert = (try? store.readAlertState()) ?? AlertState()

        let prevState = AlertEngine.State(
            utilization: 0,
            resetsAt: storedAlert.windowResetsAt.map(Date.init(timeIntervalSince1970:)),
            lastThresholdFired: storedAlert.lastThresholdFired,
            forecastFiredAt: storedAlert.forecastFiredAt.map(Date.init(timeIntervalSince1970:)),
            burnTokensPerSec: 0,
            inferredLimitTokens: inferred.sevenDayTokens ?? 0,
            currentTokens: snap.sevenDayTokens
        )
        let newState = AlertEngine.State(
            utilization: maxUtil,
            resetsAt: rate.weekly.resetsAt,
            lastThresholdFired: storedAlert.lastThresholdFired,
            forecastFiredAt: storedAlert.forecastFiredAt.map(Date.init(timeIntervalSince1970:)),
            burnTokensPerSec: snap.lastHalfHourTokensPerSecond,
            inferredLimitTokens: inferred.sevenDayTokens ?? 0,
            currentTokens: snap.sevenDayTokens
        )
        let alerts = AlertEngine.evaluate(prev: prevState, new: newState, now: now)
        #if canImport(UserNotifications)
        AlertEngine.deliver(alerts)
        #endif

        // Persist updated fire-state.
        var nextAlert = storedAlert
        if rate.weekly.resetsAt?.timeIntervalSince1970 != storedAlert.windowResetsAt {
            nextAlert.lastThresholdFired = nil
            nextAlert.forecastFiredAt = nil
            nextAlert.windowResetsAt = rate.weekly.resetsAt?.timeIntervalSince1970
        }
        for alert in alerts {
            switch alert.kind {
            case .threshold(let t):
                nextAlert.lastThresholdFired = max(nextAlert.lastThresholdFired ?? 0, t)
            case .forecast:
                nextAlert.forecastFiredAt = now.timeIntervalSince1970
            }
        }
        try? store.writeAlertState(nextAlert)

        return rate
    }
}
