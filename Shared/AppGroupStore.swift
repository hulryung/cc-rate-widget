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
    private var limitsURL:   URL { containerURL.appendingPathComponent("limits.json") }
    private var offsetsURL:  URL { containerURL.appendingPathComponent("offsets.json") }

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

    func readLimits()   throws -> InferredLimits?   { try read(limitsURL, as: InferredLimits.self) }
    func writeLimits(_ value: InferredLimits) throws { try atomicWrite(value, to: limitsURL) }

    func readOffsets()  throws -> [String: UInt64]  { (try read(offsetsURL, as: [String: UInt64].self)) ?? [:] }
    func writeOffsets(_ value: [String: UInt64]) throws { try atomicWrite(value, to: offsetsURL) }
}

// MARK: - On-disk RateData representation (snake-cased, stable)

private struct PersistedRate: Codable {
    let session: Cat
    let weekly: Cat
    let weeklySonnet: Cat
    let overage: Ov
    let fetchedAt: Double
    let status: String
    let source: String

    struct Cat: Codable { let utilization: Double; let resetsAt: Double? }
    struct Ov: Codable {
        let isEnabled: Bool
        let utilization: Double
        let spent: Double
        let limit: Double
    }

    init(from r: RateData) {
        self.session = Cat(utilization: r.session.utilization,
                           resetsAt: r.session.resetsAt?.timeIntervalSince1970)
        self.weekly = Cat(utilization: r.weekly.utilization,
                          resetsAt: r.weekly.resetsAt?.timeIntervalSince1970)
        self.weeklySonnet = Cat(utilization: r.weeklySonnet.utilization,
                                resetsAt: r.weeklySonnet.resetsAt?.timeIntervalSince1970)
        self.overage = Ov(isEnabled: r.overage.isEnabled,
                          utilization: r.overage.utilization,
                          spent: r.overage.spent,
                          limit: r.overage.limit)
        self.fetchedAt = r.fetchedAt.timeIntervalSince1970
        self.status = r.status.rawValue
        self.source = r.source.rawValue
    }

    func toRateData() -> RateData {
        RateData(
            session: CategoryData(utilization: session.utilization,
                                  resetsAt: session.resetsAt.map(Date.init(timeIntervalSince1970:))),
            weekly: CategoryData(utilization: weekly.utilization,
                                 resetsAt: weekly.resetsAt.map(Date.init(timeIntervalSince1970:))),
            weeklySonnet: CategoryData(utilization: weeklySonnet.utilization,
                                       resetsAt: weeklySonnet.resetsAt.map(Date.init(timeIntervalSince1970:))),
            overage: OverageData(isEnabled: overage.isEnabled,
                                 utilization: overage.utilization,
                                 spent: overage.spent,
                                 limit: overage.limit),
            fetchedAt: Date(timeIntervalSince1970: fetchedAt),
            status: OverallStatus(rawValue: status) ?? .unknown,
            source: RateDataSource(rawValue: source) ?? .jsonl
        )
    }
}
