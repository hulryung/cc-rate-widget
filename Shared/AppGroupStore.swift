import Foundation

final class AppGroupStore {
    static let appGroupID = "group.com.dkkang.cc-rate-widget"

    /// Bump whenever `StoredEvent`'s shape, the parsing of a JSONL line, or the cost
    /// model changes. Stored events keep a precomputed `cost`, so such a fix cannot
    /// repair them in place — the aggregator reacts to a version change by discarding
    /// the store and re-reading from source. v2: TTL-aware cache-write pricing and
    /// Claude 5 model rates.
    static let currentSchemaVersion = 2

    private let containerURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    static var shared: AppGroupStore = {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            fatalError("App Group container missing: \(appGroupID)")
        }
        return AppGroupStore(containerURL: url)
    }()

    init(containerURL: URL) {
        self.containerURL = containerURL
    }

    // MARK: - URLs
    private var rateURL:     URL { containerURL.appendingPathComponent("rate.json") }
    private var projectsURL: URL { containerURL.appendingPathComponent("projects.json") }
    private var offsetsURL:  URL { containerURL.appendingPathComponent("offsets.json") }
    private var eventsURL:   URL { containerURL.appendingPathComponent("events.json") }
    private var schemaURL:   URL { containerURL.appendingPathComponent("schema.json") }

    // MARK: - Generic read/write
    private func read<T: Decodable>(_ url: URL, as type: T.Type) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }

    private func atomicWrite<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }

    // MARK: - Public surface
    func readRate()     throws -> RateData?         { try read(rateURL, as: PersistedRate.self)?.toRateData() }
    func writeRate(_ value: RateData) throws        { try atomicWrite(PersistedRate(from: value), to: rateURL) }

    func readProjects() throws -> ProjectBreakdown? { try read(projectsURL, as: ProjectBreakdown.self) }
    func writeProjects(_ value: ProjectBreakdown) throws { try atomicWrite(value, to: projectsURL) }

    func readOffsets()  throws -> [String: UInt64]  { (try read(offsetsURL, as: [String: UInt64].self)) ?? [:] }
    func writeOffsets(_ value: [String: UInt64]) throws { try atomicWrite(value, to: offsetsURL) }

    /// Rolling per-file event store: file path → in-window events. Keyed by file so
    /// offset resets (file rotation) and file deletions can be reconciled without
    /// double-counting. Aggregator ages out events older than the 7-day window.
    func readEvents()  throws -> [String: [StoredEvent]]  { (try read(eventsURL, as: [String: [StoredEvent]].self)) ?? [:] }
    func writeEvents(_ value: [String: [StoredEvent]]) throws { try atomicWrite(value, to: eventsURL) }

    /// Version of the data already on disk. A store written before versioning existed —
    /// or one that fails to decode — reads as 1, which forces the v2 rescan.
    func readSchemaVersion() -> Int {
        ((try? read(schemaURL, as: SchemaMarker.self)) ?? nil)?.version ?? 1
    }
    func writeSchemaVersion(_ version: Int) throws {
        try atomicWrite(SchemaMarker(version: version), to: schemaURL)
    }
}

private struct SchemaMarker: Codable { let version: Int }

// MARK: - On-disk RateData representation (stable absolute usage)

private struct PersistedRate: Codable {
    let session: Cat
    let weekly: Cat
    let weeklySonnet: Cat
    let fetchedAt: Double
    let status: String
    let source: String

    var burnTokensPerSecond: Double?
    var planName: String?
    var officialFetchedAt: Double?

    struct Cat: Codable {
        let tokens: Int
        let cost: Double
        let resetsAt: Double?
        var limitTokens: Int?
        var limitKind: String?
        var officialUtilization: Double?

        init(_ c: CategoryData) {
            self.tokens = c.tokens; self.cost = c.cost
            self.resetsAt = c.resetsAt?.timeIntervalSince1970
            self.limitTokens = c.limitTokens
            self.limitKind = c.limitKind?.rawValue
            self.officialUtilization = c.officialUtilization
        }

        private enum CodingKeys: String, CodingKey { case tokens, cost, resetsAt, limitTokens, limitKind, officialUtilization }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.tokens = try c.decode(Int.self, forKey: .tokens)
            self.cost = try c.decode(Double.self, forKey: .cost)
            self.resetsAt = try c.decodeIfPresent(Double.self, forKey: .resetsAt)
            self.limitTokens = try c.decodeIfPresent(Int.self, forKey: .limitTokens)
            self.limitKind = try c.decodeIfPresent(String.self, forKey: .limitKind)
            self.officialUtilization = try c.decodeIfPresent(Double.self, forKey: .officialUtilization)
        }

        var category: CategoryData {
            CategoryData(tokens: tokens, cost: cost,
                         resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:)),
                         limitTokens: limitTokens,
                         limitKind: limitKind.flatMap(LimitKind.init(rawValue:)),
                         officialUtilization: officialUtilization)
        }
    }

    init(from r: RateData) {
        self.session = Cat(r.session)
        self.weekly = Cat(r.weekly)
        self.weeklySonnet = Cat(r.weeklySonnet)
        self.fetchedAt = r.fetchedAt.timeIntervalSince1970
        self.status = r.status.rawValue
        self.source = r.source.rawValue
        self.burnTokensPerSecond = r.burnTokensPerSecond
        self.planName = r.planName
        self.officialFetchedAt = r.officialFetchedAt?.timeIntervalSince1970
    }

    func toRateData() -> RateData {
        RateData(
            session: session.category,
            weekly: weekly.category,
            weeklySonnet: weeklySonnet.category,
            fetchedAt: Date(timeIntervalSince1970: fetchedAt),
            status: OverallStatus(rawValue: status) ?? .unknown,
            source: RateDataSource(rawValue: source) ?? .jsonl,
            burnTokensPerSecond: burnTokensPerSecond ?? 0,
            planName: planName,
            officialFetchedAt: officialFetchedAt.map(Date.init(timeIntervalSince1970:))
        )
    }
}
