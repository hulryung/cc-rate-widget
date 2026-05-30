import Foundation

final class AppGroupStore {
    static let appGroupID = "group.com.dkkang.cc-rate-widget"

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
}

// MARK: - On-disk RateData representation (stable absolute usage)

private struct PersistedRate: Codable {
    let session: Cat
    let weekly: Cat
    let weeklySonnet: Cat
    let fetchedAt: Double
    let status: String
    let source: String

    struct Cat: Codable { let tokens: Int; let cost: Double; let resetsAt: Double? }

    init(from r: RateData) {
        self.session = Cat(tokens: r.session.tokens, cost: r.session.cost,
                           resetsAt: r.session.resetsAt?.timeIntervalSince1970)
        self.weekly = Cat(tokens: r.weekly.tokens, cost: r.weekly.cost,
                          resetsAt: r.weekly.resetsAt?.timeIntervalSince1970)
        self.weeklySonnet = Cat(tokens: r.weeklySonnet.tokens, cost: r.weeklySonnet.cost,
                                resetsAt: r.weeklySonnet.resetsAt?.timeIntervalSince1970)
        self.fetchedAt = r.fetchedAt.timeIntervalSince1970
        self.status = r.status.rawValue
        self.source = r.source.rawValue
    }

    func toRateData() -> RateData {
        func cat(_ c: Cat) -> CategoryData {
            CategoryData(tokens: c.tokens, cost: c.cost,
                         resetsAt: c.resetsAt.map(Date.init(timeIntervalSince1970:)))
        }
        return RateData(
            session: cat(session),
            weekly: cat(weekly),
            weeklySonnet: cat(weeklySonnet),
            fetchedAt: Date(timeIntervalSince1970: fetchedAt),
            status: OverallStatus(rawValue: status) ?? .unknown,
            source: RateDataSource(rawValue: source) ?? .jsonl
        )
    }
}
