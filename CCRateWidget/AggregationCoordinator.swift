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
        let store = LocalStore.shared
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
        let suite = UserDefaults.standard
        func cap(_ key: String) -> Int? {
            let m = suite.double(forKey: key)
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
        // keychain token, so the bars match `/status`. Reading the keychain can raise a
        // macOS permission prompt, so it happens at most once per throttle window.
        var source: RateDataSource = .jsonl
        var officialAt: Date? = nil
        let oauthOn = suite.bool(forKey: "oauthEnabled")
        if oauthOn {
            let throttle: TimeInterval = 15 * 60
            let prev = try? store.readRate()
            var official: OfficialUsage?

            // Throttle on the last *attempt*, not the last success. Keying off success
            // meant a single failure — a denied prompt, an expired token, no network —
            // dropped us back to re-reading the keychain every 5-minute tick, so the user
            // got prompted again and again instead of once.
            let lastAttempt = prev?.officialFetchedAt
            let withinWindow = lastAttempt.map { now.timeIntervalSince($0) < throttle } ?? false

            if withinWindow, let prev, prev.source == .oauth,
               let f = prev.session.officialUtilization {
                official = OfficialUsage(
                    fiveHour: f,
                    sevenDay: prev.weekly.officialUtilization ?? 0,
                    sevenDaySonnet: prev.weeklySonnet.officialUtilization ?? 0,
                    fiveHourResetsAt: prev.session.resetsAt,
                    sevenDayResetsAt: prev.weekly.resetsAt
                )
                officialAt = lastAttempt
            } else if withinWindow {
                // Attempted recently and it didn't work. Stay on local data rather than
                // asking again; the next window will retry.
                officialAt = lastAttempt
            } else {
                official = OfficialUsage.fetch()   // reads keychain (may prompt the first time)
                officialAt = now                   // recorded either way
            }
            if let off = official {
                session = session.withOfficial(off.fiveHour, resetsAt: off.fiveHourResetsAt)
                weekly  = weekly.withOfficial(off.sevenDay, resetsAt: off.sevenDayResetsAt)
                sonnet  = sonnet.withOfficial(off.sevenDaySonnet, resetsAt: off.sevenDayResetsAt)
                source  = .oauth
            }
        }

        let rate = RateData(
            session: session, weekly: weekly, weeklySonnet: sonnet,
            fetchedAt: now,
            status: .active,
            source: source,
            burnTokensPerSecond: snap.lastHalfHourTokensPerSecond,
            planName: ClaudePlan.detect(),
            officialFetchedAt: officialAt
        )

        try store.writeRate(rate)
        return rate
    }
}
