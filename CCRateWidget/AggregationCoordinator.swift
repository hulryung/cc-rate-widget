import Foundation
import WidgetKit

@MainActor
final class AggregationCoordinator: ObservableObject {
    /// Model families Anthropic meters against a limit of their own, and so the only ones
    /// worth a card of their own. Everything else — Opus, Sonnet — draws down the same
    /// all-model week the top card already shows, so a second bar for it would be the same
    /// quota counted twice, and `/status` doesn't list them either.
    static let separatelyMeteredFamilies: Set<String> = ["fable"]

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
            let r = RateData(windows: [], fetchedAt: now,
                             status: .noLocalData, source: .noLocalData)
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

        // Weekly denominator: the same idea one window up. Without it the card people look at
        // first was the only one with no bar at all, since a weekly cap is the one number
        // Anthropic doesn't publish and most people never type in.
        let weeklyLimit: Int?; let weeklyKind: LimitKind?
        if let c = weeklyCap { weeklyLimit = c; weeklyKind = .userLimit }
        else if let p = snap.typicalWeeklyPeak { weeklyLimit = p; weeklyKind = .peakPace }
        else { weeklyLimit = nil; weeklyKind = nil }

        let localSession = cat(tokens: snap.fiveHourTokens, cost: snap.fiveHourCost,
                               earliest: snap.earliestInFiveHour, window: 5 * 3600,
                               limit: sessionLimit, kind: sessionKind)
        let localWeekly = cat(tokens: snap.sevenDayTokens, cost: snap.sevenDayCost,
                              earliest: snap.earliestInSevenDay, window: 7 * 86400,
                              limit: weeklyLimit, kind: weeklyKind)

        // Local windows: what we can measure ourselves.
        var windows: [UsageWindow] = [
            UsageWindow(id: RateData.weeklyID, title: "Weekly", subtitle: "7 days", data: localWeekly),
            UsageWindow(id: RateData.sessionID, title: "Session", subtitle: "5 hours", data: localSession),
        ]
        for (family, totals) in snap.sevenDayByFamily.sorted(by: { $0.value.tokens > $1.value.tokens })
        where totals.tokens > 0 && Self.separatelyMeteredFamilies.contains(family) {
            windows.append(UsageWindow(
                id: "weekly_family_\(family)",
                title: "Weekly · \(family.capitalized)", subtitle: "7 days",
                data: cat(tokens: totals.tokens, cost: totals.cost,
                          earliest: snap.earliestInSevenDay, window: 7 * 86400,
                          limit: snap.typicalWeeklyPeakByFamily[family],
                          kind: snap.typicalWeeklyPeakByFamily[family] != nil ? .peakPace : nil)))
        }

        /// Local tokens and dollars measured over *Anthropic's* window, not ours.
        ///
        /// Their windows are fixed blocks: the weekly one had just rolled over when
        /// this was written, so the official figure was 0% while our rolling 7-day
        /// count still said 99.7M. Deriving the block start from `resets_at` makes the
        /// two halves of a card describe the same period.
        ///
        /// Without a `resets_at` there is nothing to anchor to, so the window shows its
        /// percentage alone rather than a number covering the wrong span.
        func localData(id: String, scope: String?, resetsAt: Date?) -> CategoryData? {
            guard let resetsAt else { return nil }
            let period: TimeInterval = id == RateData.sessionID ? 5 * 3600 : 7 * 86400
            let start = resetsAt.addingTimeInterval(-period)
            let family = scope.map { ModelFamily.key(forDisplayName: $0) }
            if let family, family.isEmpty { return nil }
            let t = snap.totals(since: start, family: family)
            return CategoryData(tokens: t.tokens, cost: t.cost, resetsAt: resetsAt)
        }

        var source: RateDataSource = .jsonl
        var officialAt: Date? = nil
        let oauthOn = suite.bool(forKey: "oauthEnabled")

        // Anthropic's own percentages, left for us by Claude Code's status-line script.
        // Preferred over the Keychain path below and needing no opt-in of its own: writing
        // that file is the opt-in, and reading it asks macOS for nothing. Only the two
        // account-wide windows come this way, so per-family cards keep their local totals
        // instead of vanishing the way the Keychain path replaces the whole list.
        if let statusLine = StatusLineUsage.read(from: store.container, now: now) {
            func overlay(_ id: String, _ window: StatusLineUsage.Window?) {
                guard let window, let i = windows.firstIndex(where: { $0.id == id }) else { return }
                let base = localData(id: id, scope: nil, resetsAt: window.resetsAt)
                    ?? CategoryData(tokens: 0, cost: 0, resetsAt: window.resetsAt)
                windows[i].data = base.withOfficial(window.utilization, resetsAt: window.resetsAt)
            }
            overlay(RateData.weeklyID, statusLine.sevenDay)
            overlay(RateData.sessionID, statusLine.fiveHour)

            // Re-cut the per-family windows over Anthropic's block too. Left on our rolling
            // seven days they contradict the card above them — the first run of this showed
            // "Weekly 55.71M" over "Weekly · Opus 63.45M", a total smaller than one of its
            // own parts. Same reset, same span, so the parts add up to the whole again.
            if let weeklyReset = statusLine.sevenDay?.resetsAt {
                let start = weeklyReset.addingTimeInterval(-7 * 86400)
                windows.removeAll { $0.id.hasPrefix("weekly_family_") }
                let families = snap.sevenDayByFamily.keys
                    .filter { Self.separatelyMeteredFamilies.contains($0) }
                    .map { (family: $0, totals: snap.totals(since: start, family: $0)) }
                    .filter { $0.totals.tokens > 0 }
                    .sorted { $0.totals.tokens > $1.totals.tokens }
                windows.append(contentsOf: families.map { entry in
                    let pace = snap.typicalWeeklyPeakByFamily[entry.family]
                    return UsageWindow(
                        id: "weekly_family_\(entry.family)",
                        title: "Weekly · \(entry.family.capitalized)", subtitle: "7 days",
                        data: CategoryData(tokens: entry.totals.tokens, cost: entry.totals.cost,
                                           resetsAt: weeklyReset,
                                           limitTokens: pace,
                                           limitKind: pace != nil ? .peakPace : nil))
                })
            }
            source = .statusLine
        } else if oauthOn {
            let throttle: TimeInterval = 15 * 60
            let prev = try? store.readRate()
            var official: OfficialUsage?

            // Throttle on the last *attempt*, not the last success. Keying off success
            // meant a single failure — a denied prompt, an expired token, no network —
            // dropped us back to re-reading the keychain every 5-minute tick, so the user
            // got prompted again and again instead of once.
            let lastAttempt = prev?.officialFetchedAt
            let recentlyTried = lastAttempt.map { now.timeIntervalSince($0) < throttle } ?? false

            // A cached window whose reset has already passed describes the previous block.
            // Reusing it after a rollover is what left "Weekly · Fable" quoting last week's
            // reset time — and, since the local totals are now derived from that instant,
            // last week's tokens too. A rollover is exactly when someone looks, so refetch.
            let cacheRolledOver = prev?.windows.contains {
                ($0.data.officialUtilization != nil) && ($0.data.resetsAt.map { $0 <= now } ?? false)
            } ?? false
            let withinWindow = recentlyTried && !cacheRolledOver

            if withinWindow, let prev, prev.source == .oauth, !prev.windows.isEmpty {
                // Reuse the cached window list verbatim — its titles came from Anthropic
                // and can't be recomputed from an id — but refresh the local numbers, which
                // are cheap and did move since the last keychain read.
                windows = prev.windows.map { w in
                    guard let u = w.data.officialUtilization else { return w }
                    // The id carries the scope label after the colon ("weekly_scoped:Fable").
                    let scope = w.id.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init)
                    let base = localData(id: w.id, scope: scope, resetsAt: w.data.resetsAt)
                        ?? CategoryData(tokens: 0, cost: 0, resetsAt: w.data.resetsAt)
                    var out = w
                    out.data = base.withOfficial(u, resetsAt: w.data.resetsAt)
                    return out
                }
                source = .oauth
                officialAt = lastAttempt
            } else if withinWindow {
                // Attempted recently and it didn't work. Stay on local data rather than
                // asking again; the next window will retry.
                officialAt = lastAttempt
            } else {
                official = OfficialUsage.fetch()   // reads keychain (may prompt the first time)
                officialAt = now                   // recorded either way

                // Mirror Anthropic's own list rather than a fixed three. It reports scoped
                // per-model windows (e.g. "Fable") that come and go, so the set is theirs
                // to decide; we attach the numbers we measured where a window maps to ours.
                if let off = official, !off.limits.isEmpty {
                    // A scoped window sometimes arrives without its own resets_at (it did,
                    // minutes after a weekly rollover). It shares the weekly block, so
                    // borrow that reset rather than dropping the window's numbers.
                    let weeklyReset = off.limits.first { $0.kind == "weekly_all" }?.resetsAt
                    windows = off.limits.map { limit in
                        let reset = limit.resetsAt ?? (limit.kind.hasPrefix("weekly") ? weeklyReset : nil)
                        let base = localData(id: limit.id, scope: limit.scopeLabel, resetsAt: reset)
                            ?? CategoryData(tokens: 0, cost: 0, resetsAt: reset)
                        return UsageWindow(
                            id: limit.id,
                            title: limit.title,
                            subtitle: limit.subtitle,
                            data: base.withOfficial(limit.utilization, resetsAt: reset))
                    }
                    source = .oauth
                }
            }
        }

        // Anthropic lists session first, but the weekly window is what people plan around
        // and every surface gives its first entry the largest treatment. Order for the
        // reader, not for the wire.
        windows.sort { a, b in
            func rank(_ w: UsageWindow) -> Int {
                if w.id == RateData.weeklyID { return 0 }
                if w.id == RateData.sessionID { return 2 }
                return 1                              // scoped per-model windows
            }
            return rank(a) < rank(b)
        }

        let rate = RateData(
            windows: windows,
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
