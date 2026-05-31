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
        guard timer == nil else { return }   // idempotent: ignore duplicate start() calls
        runOnce()
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

        let now = Date()

        guard FileManager.default.fileExists(atPath: root.path) else {
            let empty = CategoryData(tokens: 0, cost: 0, resetsAt: nil)
            let r = RateData(session: empty, weekly: empty, weeklySonnet: empty,
                             fetchedAt: now, status: .noLocalData, source: .noLocalData)
            try store.writeRate(r)
            return r
        }

        let aggregator = JSONLAggregator(rootDir: root, store: store)
        let snap = try aggregator.aggregate(now: now)
        try store.writeProjects(snap.projects)

        // Optional user-entered caps (millions of tokens; 0 = unset → no percentage).
        let suite = UserDefaults(suiteName: AppGroupStore.appGroupID)
        func cap(_ key: String) -> Int? {
            let m = suite?.double(forKey: key) ?? 0
            return m > 0 ? Int(m * 1_000_000) : nil
        }
        let fiveHourCap = cap(SettingsStore.fiveHourLimitKey)
        let weeklyCap   = cap(SettingsStore.weeklyLimitKey)

        func cat(tokens: Int, cost: Double, earliest: Date?, window: TimeInterval,
                 limit: Int?, kind: LimitKind?) -> CategoryData {
            CategoryData(tokens: tokens, cost: cost,
                         resetsAt: earliest.map { $0.addingTimeInterval(window) },
                         limitTokens: limit, limitKind: kind)
        }

        // Session 5h denominator: user cap if set, else the self-calibrated P90 "typical peak".
        let sessionLimit: Int?; let sessionKind: LimitKind?
        if let c = fiveHourCap { sessionLimit = c; sessionKind = .userLimit }
        else if let p = snap.typicalFiveHourPeak { sessionLimit = p; sessionKind = .typicalPeak }
        else { sessionLimit = nil; sessionKind = nil }

        var session = cat(tokens: snap.fiveHourTokens, cost: snap.fiveHourCost,
                          earliest: snap.earliestInFiveHour, window: 5 * 3600,
                          limit: sessionLimit, kind: sessionKind)
        var weekly = cat(tokens: snap.sevenDayTokens, cost: snap.sevenDayCost,
                         earliest: snap.earliestInSevenDay, window: 7 * 86400,
                         limit: weeklyCap, kind: weeklyCap != nil ? .userLimit : nil)
        var sonnet = cat(tokens: snap.sevenDaySonnetTokens, cost: 0,
                         earliest: snap.earliestInSevenDay, window: 7 * 86400,
                         limit: nil, kind: nil)

        // Official Anthropic % (opt-in): overlays the real utilization from Claude Code's
        // keychain token, so the bars match `/status`. Falls back to local on any failure.
        var source: RateDataSource = .jsonl
        let oauthOn = (suite?.bool(forKey: "oauthEnabled")) ?? false
        if oauthOn, let off = OfficialUsage.fetch() {
            session = session.withOfficial(off.fiveHour, resetsAt: off.fiveHourResetsAt)
            weekly  = weekly.withOfficial(off.sevenDay, resetsAt: off.sevenDayResetsAt)
            sonnet  = sonnet.withOfficial(off.sevenDaySonnet, resetsAt: off.sevenDayResetsAt)
            source  = .oauth
        }

        let rate = RateData(
            session: session, weekly: weekly, weeklySonnet: sonnet,
            fetchedAt: now,
            status: .active,
            source: source,
            burnTokensPerSecond: snap.lastHalfHourTokensPerSecond,
            planName: ClaudePlan.detect()
        )

        try store.writeRate(rate)
        return rate
    }
}
