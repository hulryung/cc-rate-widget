import Foundation

/// A single assistant event retained in the rolling window store. Compact on-disk keys
/// keep `events.json` small even with tens of thousands of events.
struct StoredEvent: Codable, Equatable {
    let t: Double        // event timestamp, epoch seconds
    let tokens: Int      // utilizationTokens (input + output + cacheWrite)
    let sonnet: Bool     // model matched /sonnet/i
    let cost: Double     // USD
    let project: String  // cwd
    let id: String?      // dedupe key (messageId:requestId); nil = always counted

    init(t: Double, tokens: Int, sonnet: Bool, cost: Double, project: String, id: String? = nil) {
        self.t = t; self.tokens = tokens; self.sonnet = sonnet
        self.cost = cost; self.project = project; self.id = id
    }

    enum CodingKeys: String, CodingKey {
        case t, tokens = "k", sonnet = "s", cost = "c", project = "p", id = "i"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.t = try c.decode(Double.self, forKey: .t)
        self.tokens = try c.decode(Int.self, forKey: .tokens)
        self.sonnet = try c.decode(Bool.self, forKey: .sonnet)
        self.cost = try c.decode(Double.self, forKey: .cost)
        self.project = try c.decode(String.self, forKey: .project)
        self.id = try c.decodeIfPresent(String.self, forKey: .id)
    }
}

struct AggregationSnapshot {
    var fiveHourTokens: Int
    var sevenDayTokens: Int
    var sevenDaySonnetTokens: Int

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
}

final class JSONLAggregator {
    private let rootDir: URL
    private let store: AppGroupStore
    private let fiveHours: TimeInterval = 5 * 3600
    private let sevenDays: TimeInterval = 7 * 86400
    private let halfHour: TimeInterval = 1800

    init(rootDir: URL, store: AppGroupStore) {
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
                    sonnet: evt.model.lowercased().contains("sonnet"),
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

        var fiveHourTokens = 0, sevenDayTokens = 0, sevenDaySonnetTokens = 0
        var fiveHourCost = 0.0, sevenDayCost = 0.0
        var earliest5h: Double?, earliest7d: Double?
        var halfHourTokens = 0
        var perProjectTokens: [String: Int] = [:]
        var perProjectCost:   [String: Double] = [:]
        var blockTotals: [Int: Int] = [:]   // fixed 5h block index → tokens (for P90 peak)
        var seen = Set<String>()            // dedupe: same event logged in multiple files

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
            if e.sonnet { sevenDaySonnetTokens += e.tokens }
            if age <= halfHour { halfHourTokens += e.tokens }

            perProjectTokens[e.project, default: 0] += e.tokens
            perProjectCost[e.project, default: 0]   += e.cost

            blockTotals[Int(e.t / fiveHours), default: 0] += e.tokens
        }

        // Typical 5-hour peak = P90 of past active blocks (exclude the in-progress block).
        let currentBlock = Int(nowT / fiveHours)
        let activeBlocks = blockTotals.filter { $0.key != currentBlock && $0.value > 0 }.values.sorted()
        let typicalPeak = activeBlocks.count >= 3 ? percentile(activeBlocks, 0.90) : nil

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
            sevenDaySonnetTokens: sevenDaySonnetTokens,
            fiveHourCost: fiveHourCost,
            sevenDayCost: sevenDayCost,
            earliestInFiveHour: earliest5h.map(Date.init(timeIntervalSince1970:)),
            earliestInSevenDay: earliest7d.map(Date.init(timeIntervalSince1970:)),
            projects: ProjectBreakdown(entries: entries),
            lastHalfHourTokensPerSecond: Double(halfHourTokens) / halfHour,
            typicalFiveHourPeak: typicalPeak
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
