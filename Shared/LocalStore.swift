import Foundation

/// On-disk state for the app: the computed snapshot, the per-project breakdown, and the
/// rolling event store the aggregator maintains.
///
/// This used to live in an App Group container so a widget extension could read it. The
/// widget is gone — a sandboxed extension cannot carry an App Group entitlement without a
/// provisioning profile validating it, which made the widget unbuildable outside a fully
/// provisioned machine. Nothing reads this but the app now, so it lives in Application
/// Support and the app needs no entitlement at all.
final class LocalStore {
    /// Kept only so settings written under the old App Group suite can be migrated.
    static let legacyAppGroupID = "group.com.dkkang.cc-rate-widget"

    /// Bump when `StoredEvent`'s shape, JSONL parsing, or the cost model changes. Stored
    /// events carry a precomputed cost, so such a fix cannot repair them in place — the
    /// aggregator reacts to a version change by discarding the store and re-reading.
    static let currentSchemaVersion = 2

    private let containerURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    static var shared: LocalStore = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Claude Rate Widget", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let store = LocalStore(containerURL: base)
        store.migrateFromAppGroupIfNeeded()
        return store
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

    /// Rolling per-file event store: file path → in-window events. Keyed by file so offset
    /// resets (rotation) and deletions reconcile without double-counting.
    func readEvents()  throws -> [String: [StoredEvent]]  { (try read(eventsURL, as: [String: [StoredEvent]].self)) ?? [:] }
    func writeEvents(_ value: [String: [StoredEvent]]) throws { try atomicWrite(value, to: eventsURL) }

    /// A store written before versioning existed — or one that fails to decode — reads as
    /// 1, which forces the v2 rescan.
    func readSchemaVersion() -> Int {
        ((try? read(schemaURL, as: SchemaMarker.self)) ?? nil)?.version ?? 1
    }
    func writeSchemaVersion(_ version: Int) throws {
        try atomicWrite(SchemaMarker(version: version), to: schemaURL)
    }

    // MARK: - Migration off the App Group

    /// Moves state and settings out of the old App Group container the first time this
    /// build runs, so dropping the entitlement doesn't silently reset the user's window,
    /// their limits, or whether official usage was enabled.
    private func migrateFromAppGroupIfNeeded() {
        let fm = FileManager.default
        let legacy = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(Self.legacyAppGroupID)", isDirectory: true)
        guard fm.fileExists(atPath: legacy.path) else { return }

        // Files: only move what we don't already have, so a re-run never clobbers newer state.
        for name in ["rate.json", "projects.json", "offsets.json", "events.json", "schema.json"] {
            let from = legacy.appendingPathComponent(name)
            let to = containerURL.appendingPathComponent(name)
            guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { continue }
            try? fm.copyItem(at: from, to: to)
        }

        Self.migrateSettings(legacyContainer: legacy)
    }

    /// Copies the old settings across.
    ///
    /// Read from the plist path directly, not `UserDefaults(suiteName:)`: while the App
    /// Group entitlement existed the suite resolved *inside* the container, and without
    /// the entitlement that same name resolves to an empty domain in ~/Library/Preferences.
    /// Going through UserDefaults here silently migrates nothing.
    /// Deliberately has no "already migrated" flag. Per-key `object(forKey:) == nil` is
    /// enough for idempotency — a value the user has since changed is never overwritten,
    /// because changing it stores something. A flag adds a way to fail permanently: set it
    /// during a migration that copied nothing, and the fixed version can never run.
    static func migrateSettings(legacyContainer: URL) {
        let plist = legacyContainer
            .appendingPathComponent("Library/Preferences/\(legacyAppGroupID).plist")
        guard let data = try? Data(contentsOf: plist),
              let old = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any] else { return }

        let target = UserDefaults.standard
        for key in ["oauthEnabled", "hotkeyEnabled", "fiveHourLimitMillions",
                    "weeklyLimitMillions", "claudeRateLimitTier", "credentials"] {
            if target.object(forKey: key) == nil, let value = old[key] {
                target.set(value, forKey: key)
            }
        }
    }

    /// Runs the settings migration exactly once per process, before anything reads
    /// `UserDefaults.standard`. `static let` gives us the run-once guarantee for free.
    static let settingsMigrated: Void = {
        let legacy = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(legacyAppGroupID)", isDirectory: true)
        migrateSettings(legacyContainer: legacy)
    }()

}

private struct SchemaMarker: Codable { let version: Int }

// MARK: - On-disk RateData representation

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
