import Foundation

/// A single assistant event retained in the rolling window store. Compact on-disk keys
/// keep `events.json` small even with tens of thousands of events.
struct StoredEvent: Codable, Equatable {
    let t: Double        // event timestamp, epoch seconds
    let tokens: Int      // utilizationTokens (input + output + cacheWrite)
    /// Model family — "opus", "fable", "sonnet", … Was a `sonnet: Bool`, which threw away
    /// every other family, so a per-model window like Anthropic's "Weekly · Fable" had no
    /// local tokens to show and rendered a misleading 0.
    let family: String
    let cost: Double     // USD
    let project: String  // cwd
    let id: String?      // dedupe key (messageId:requestId); nil = always counted

    init(t: Double, tokens: Int, family: String, cost: Double, project: String, id: String? = nil) {
        self.t = t; self.tokens = tokens; self.family = family
        self.cost = cost; self.project = project; self.id = id
    }

    enum CodingKeys: String, CodingKey {
        case t, tokens = "k", family = "f", cost = "c", project = "p", id = "i"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.t = try c.decode(Double.self, forKey: .t)
        self.tokens = try c.decode(Int.self, forKey: .tokens)
        self.family = try c.decodeIfPresent(String.self, forKey: .family) ?? ""
        self.cost = try c.decode(Double.self, forKey: .cost)
        self.project = try c.decode(String.self, forKey: .project)
        self.id = try c.decodeIfPresent(String.self, forKey: .id)
    }
}

struct AggregationSnapshot {
    var fiveHourTokens: Int
    var sevenDayTokens: Int
    /// 7-day totals split by model family, so a scoped per-model window can show real
    /// numbers instead of a zero.
    var sevenDayByFamily: [String: (tokens: Int, cost: Double)]

    var fiveHourCost: Double
    var sevenDayCost: Double

    var earliestInFiveHour: Date?
    var earliestInSevenDay: Date?

    var projects: ProjectBreakdown

    /// Burn rate over the last 30 minutes, in tokens per second.
    var lastHalfHourTokensPerSecond: Double

    /// P90 of the user's own historical 5-hour block token totals — a self-calibrated
    /// "typical peak" denominator. nil until there are enough active blocks to be meaningful.
    var typicalFiveHourPeak: Int?

    /// Seven days at the pace of the heaviest whole day in the window — the weekly
    /// equivalent, for accounts that never entered a cap. Days rather than a percentile
    /// over past weeks because the store keeps 7 days: there is no second week to compare
    /// against, and there never will be. nil until three whole days have usage in them.
    var typicalWeeklyPeak: Int?

    /// The same calculation per model family, so a window Anthropic meters separately can
    /// carry a bar of its own. A family is measured against its own days, not a share of
    /// the total: a model used in short bursts would otherwise read as permanently idle.
    var typicalWeeklyPeakByFamily: [String: Int] = [:]

    /// Deduplicated in-window events, kept so totals can be recomputed over an arbitrary
    /// period. Anthropic's windows are fixed blocks with their own start times, not the
    /// rolling windows we compute — right after a weekly reset the two disagree completely,
    /// which is how a card came to read "99.7M tok" beside "0%".
    var events: [StoredEvent] = []

    /// Tokens and cost since an instant, optionally for one model family.
    func totals(since start: Date, family: String? = nil) -> (tokens: Int, cost: Double) {
        let from = start.timeIntervalSince1970
        var tokens = 0
        var cost = 0.0
        for e in events where e.t >= from {
            if let family, e.family != family { continue }
            tokens += e.tokens
            cost += e.cost
        }
        return (tokens, cost)
    }
}

final class JSONLAggregator {
    private let rootDir: URL
    private let store: LocalStore
    private let fiveHours: TimeInterval = 5 * 3600
    private let sevenDays: TimeInterval = 7 * 86400
    private let halfHour: TimeInterval = 1800

    init(rootDir: URL, store: LocalStore) {
        self.rootDir = rootDir
        self.store = store
    }

    /// Ingests newly-appended JSONL lines into a persistent per-file rolling event store,
    /// ages out events older than 7 days, then computes the snapshot from the FULL retained
    /// set. This is what makes the 5h/7d windows correct across ticks — incremental tailing
    /// alone would only ever see each event once and could not reconstruct a rolling window.
    func aggregate(now: Date = Date()) throws -> AggregationSnapshot {
        var offsets = (try? store.readOffsets()) ?? [:]
        var events  = (try? store.readEvents()) ?? [:]
        let cutoff  = now.addingTimeInterval(-sevenDays).timeIntervalSince1970

        let files = try listJsonlFiles()
        let currentPaths = Set(files.map(\.path))

        // Schema migration: stored events carry a precomputed cost, so a pricing or
        // parsing fix can't repair them in place. Drop the store and re-read from source.
        // A file untouched since the cutoff can only contain events that have already
        // aged out, so seek past it rather than re-parsing hundreds of MB of history.
        if store.readSchemaVersion() != LocalStore.currentSchemaVersion {
            events.removeAll()
            offsets.removeAll()
            for url in files where modifiedAt(at: url.path).map({ $0 < cutoff }) ?? false {
                offsets[url.path] = fileSize(at: url.path)
            }
            try? store.writeSchemaVersion(LocalStore.currentSchemaVersion)
        }

        // Orphan cleanup: a file that no longer exists keeps no events or offset.
        for key in events.keys where !currentPaths.contains(key) { events.removeValue(forKey: key) }
        for key in offsets.keys where !currentPaths.contains(key) { offsets.removeValue(forKey: key) }

        for url in files {
            let path = url.path

            // Detect rotation/truncation: if the file is now smaller than our stored offset,
            // the previously-ingested bytes are gone. Drop that file's events and re-read
            // from 0 so we never double-count.
            let size = fileSize(at: path)
            if let prev = offsets[path], size < prev {
                events[path] = []
                offsets[path] = 0
            }

            let tailer = JSONLTailer(url: url)
            let (lines, newOffset) = try tailer.tail(from: offsets[path] ?? 0)
            offsets[path] = newOffset

            guard !lines.isEmpty else { continue }
            var bucket = events[path] ?? []
            for line in lines {
                guard let evt = JSONLEvent.decode(line: line) else { continue }
                let t = evt.timestamp.timeIntervalSince1970
                guard t >= cutoff else { continue }   // skip events already outside the window
                bucket.append(StoredEvent(
                    t: t,
                    tokens: evt.usage.utilizationTokens,
                    family: ModelFamily.of(evt.model),
                    cost: Pricing.cost(model: evt.model, usage: evt.usage),
                    project: evt.cwd,
                    id: evt.dedupeKey
                ))
            }
            events[path] = bucket
        }

        // Age out events that have fallen out of the 7-day window; drop empty buckets.
        for path in Array(events.keys) {
            let kept = events[path]!.filter { $0.t >= cutoff }
            if kept.isEmpty { events.removeValue(forKey: path) }
            else { events[path] = kept }
        }

        try store.writeOffsets(offsets)
        try store.writeEvents(events)

        return Self.computeSnapshot(events: events.values.flatMap { $0 }, now: now)
    }

    /// Pure window computation over the full retained event set. Unit-testable in isolation.
    static func computeSnapshot(events: [StoredEvent], now: Date) -> AggregationSnapshot {
        let fiveHours: TimeInterval = 5 * 3600
        let sevenDays: TimeInterval = 7 * 86400
        let halfHour: TimeInterval = 1800
        let nowT = now.timeIntervalSince1970

        var fiveHourTokens = 0, sevenDayTokens = 0
        var byFamily: [String: (tokens: Int, cost: Double)] = [:]
        var fiveHourCost = 0.0, sevenDayCost = 0.0
        var earliest5h: Double?, earliest7d: Double?
        var halfHourTokens = 0
        var perProjectTokens: [String: Int] = [:]
        var perProjectCost:   [String: Double] = [:]
        var blockTotals: [Int: Int] = [:]   // fixed 5h block index → tokens (for P90 peak)
        var dayTotals: [Int: Int] = [:]     // local-day index → tokens (for the weekly pace)
        var dayTotalsByFamily: [String: [Int: Int]] = [:]   // the same, per model family
        var seen = Set<String>()            // dedupe: same event logged in multiple files
        var kept: [StoredEvent] = []

        // Days are bucketed by the user's calendar, not UTC: an epoch-aligned day starts at
        // 9am in Seoul and would cut every working day in two, halving the peak we calibrate
        // against. One fixed offset ignores a DST change inside the window, which can only
        // move a single boundary by an hour — immaterial next to a day's total.
        let tzOffset = Double(TimeZone.current.secondsFromGMT(for: now))

        for e in events {
            let age = nowT - e.t
            if age < 0 || age > sevenDays { continue }
            if let id = e.id {
                if seen.contains(id) { continue }
                seen.insert(id)
            }

            if age <= fiveHours {
                fiveHourTokens += e.tokens
                fiveHourCost   += e.cost
                if earliest5h == nil || e.t < earliest5h! { earliest5h = e.t }
            }
            sevenDayTokens += e.tokens
            sevenDayCost   += e.cost
            if earliest7d == nil || e.t < earliest7d! { earliest7d = e.t }
            if !e.family.isEmpty {
                var f = byFamily[e.family] ?? (0, 0)
                f.tokens += e.tokens; f.cost += e.cost
                byFamily[e.family] = f
            }
            if age <= halfHour { halfHourTokens += e.tokens }

            kept.append(e)
            perProjectTokens[e.project, default: 0] += e.tokens
            perProjectCost[e.project, default: 0]   += e.cost

            blockTotals[Int(e.t / fiveHours), default: 0] += e.tokens
            let day = Int((e.t + tzOffset) / 86400)
            dayTotals[day, default: 0] += e.tokens
            if !e.family.isEmpty { dayTotalsByFamily[e.family, default: [:]][day, default: 0] += e.tokens }
        }

        // Typical 5-hour peak = P90 of past active blocks (exclude the in-progress block).
        let currentBlock = Int(nowT / fiveHours)
        let activeBlocks = blockTotals.filter { $0.key != currentBlock && $0.value > 0 }.values.sorted()
        let typicalPeak = activeBlocks.count >= 3 ? percentile(activeBlocks, 0.90) : nil

        // Weekly pace = the heaviest whole day, times seven. Both edge buckets are partial —
        // today is still filling, and the oldest is cut off by the 7-day retention — so
        // neither can stand in for a day's usage, which leaves six candidates. Too few for a
        // percentile to mean anything (P90 of six samples IS the maximum), so this takes the
        // peak outright rather than dressing it up as a statistic. Three active days is the
        // same floor the 5-hour peak uses: below that, one unusual day is the whole scale.
        let today = Int((nowT + tzOffset) / 86400)
        func peakPace(_ totals: [Int: Int]) -> Int? {
            let wholeDays = totals.filter { $0.key < today && $0.key >= today - 6 && $0.value > 0 }.values
            return wholeDays.count >= 3 ? wholeDays.max().map { $0 * 7 } : nil
        }
        let weeklyPace = peakPace(dayTotals)
        let familyPace = dayTotalsByFamily.compactMapValues(peakPace)

        let entries = perProjectTokens.map { (cwd, tokens) in
            ProjectBreakdown.Entry(
                displayName: (cwd as NSString).lastPathComponent,
                path: cwd,
                tokens: tokens,
                cost: perProjectCost[cwd] ?? 0
            )
        }

        return AggregationSnapshot(
            fiveHourTokens: fiveHourTokens,
            sevenDayTokens: sevenDayTokens,
            sevenDayByFamily: byFamily,
            fiveHourCost: fiveHourCost,
            sevenDayCost: sevenDayCost,
            earliestInFiveHour: earliest5h.map(Date.init(timeIntervalSince1970:)),
            earliestInSevenDay: earliest7d.map(Date.init(timeIntervalSince1970:)),
            projects: ProjectBreakdown(entries: entries),
            lastHalfHourTokensPerSecond: Double(halfHourTokens) / halfHour,
            typicalFiveHourPeak: typicalPeak,
            typicalWeeklyPeak: weeklyPace,
            typicalWeeklyPeakByFamily: familyPace,
            events: kept
        )
    }

    /// Linear-interpolation-free percentile (nearest-rank) over a pre-sorted ascending array.
    private static func percentile(_ sorted: [Int], _ p: Double) -> Int {
        guard !sorted.isEmpty else { return 0 }
        let idx = max(0, min(sorted.count - 1, Int((Double(sorted.count) * p).rounded(.down))))
        return sorted[idx]
    }

    private func fileSize(at path: String) -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
    }

    /// Last-write time as epoch seconds. nil when unreadable, which callers treat as
    /// "can't prove it's stale" and re-read the file.
    private func modifiedAt(at path: String) -> Double? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else { return nil }
        return date.timeIntervalSince1970
    }

    private func listJsonlFiles() throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: rootDir,
                                             includingPropertiesForKeys: [.isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else {
            return []
        }
        var out: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "jsonl" { out.append(url) }
        }
        return out
    }
}
