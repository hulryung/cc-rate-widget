import Foundation

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

    func aggregate(now: Date = Date()) throws -> AggregationSnapshot {
        var offsets = (try? store.readOffsets()) ?? [:]
        var fiveHourTokens = 0
        var sevenDayTokens = 0
        var sevenDaySonnetTokens = 0
        var fiveHourCost = 0.0
        var sevenDayCost = 0.0
        var earliest5h: Date?
        var earliest7d: Date?
        var halfHourTokens = 0
        var perProjectTokens: [String: Int] = [:]
        var perProjectCost:   [String: Double] = [:]

        for url in try listJsonlFiles() {
            let off = offsets[url.path] ?? 0
            let tailer = JSONLTailer(url: url)
            let (lines, newOffset) = try tailer.tail(from: off)
            offsets[url.path] = newOffset

            for line in lines {
                guard let evt = JSONLEvent.decode(line: line) else { continue }
                accumulate(
                    event: evt,
                    now: now,
                    fiveHourTokens: &fiveHourTokens,
                    sevenDayTokens: &sevenDayTokens,
                    sevenDaySonnetTokens: &sevenDaySonnetTokens,
                    fiveHourCost: &fiveHourCost,
                    sevenDayCost: &sevenDayCost,
                    earliest5h: &earliest5h,
                    earliest7d: &earliest7d,
                    halfHourTokens: &halfHourTokens,
                    perProjectTokens: &perProjectTokens,
                    perProjectCost: &perProjectCost
                )
            }
        }

        try store.writeOffsets(offsets)

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
            earliestInFiveHour: earliest5h,
            earliestInSevenDay: earliest7d,
            projects: ProjectBreakdown(entries: entries),
            lastHalfHourTokensPerSecond: Double(halfHourTokens) / halfHour
        )
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

    private func accumulate(
        event evt: JSONLEvent, now: Date,
        fiveHourTokens: inout Int, sevenDayTokens: inout Int, sevenDaySonnetTokens: inout Int,
        fiveHourCost: inout Double, sevenDayCost: inout Double,
        earliest5h: inout Date?, earliest7d: inout Date?,
        halfHourTokens: inout Int,
        perProjectTokens: inout [String: Int],
        perProjectCost: inout [String: Double]
    ) {
        let age = now.timeIntervalSince(evt.timestamp)
        if age < 0 || age > sevenDays { return }
        let tokens = evt.usage.utilizationTokens
        let cost = Pricing.cost(model: evt.model, usage: evt.usage)

        if age <= fiveHours {
            fiveHourTokens += tokens
            fiveHourCost   += cost
            if earliest5h == nil || evt.timestamp < earliest5h! { earliest5h = evt.timestamp }
        }
        sevenDayTokens += tokens
        sevenDayCost   += cost
        if earliest7d == nil || evt.timestamp < earliest7d! { earliest7d = evt.timestamp }
        if evt.model.lowercased().contains("sonnet") {
            sevenDaySonnetTokens += tokens
        }
        if age <= halfHour {
            halfHourTokens += tokens
        }
        perProjectTokens[evt.cwd, default: 0] += tokens
        perProjectCost[evt.cwd, default: 0]   += cost
    }
}
