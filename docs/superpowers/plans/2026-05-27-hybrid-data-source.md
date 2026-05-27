# Hybrid Data Source (1.7) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate Claude Rate Widget from OAuth-only sourcing to JSONL-primary sourcing with OAuth as an opt-in supplement, adding per-project attribution and burn-rate alerts.

**Architecture:** A main-app-side `JSONLAggregator` tails `~/.claude/projects/**/*.jsonl` every 5 minutes, builds 5h/7d/7d-Sonnet rolling windows, and writes three JSON snapshots (`rate.json`, `projects.json`, `limits.json`) into the App Group container. A `LimitInferrer` derives utilization % from P90 history (or cached-official OAuth values). An `AlertEngine` diffs prev vs new and fires `UNUserNotification` on threshold crossings or burn-rate ETA. The widget extension reads the snapshots unchanged in shape; the Large variant gains a Top-3 project strip. App sandbox is dropped on the main app to enable `~/.claude/` reads.

**Tech Stack:** Swift 5.9, SwiftUI, WidgetKit, XCTest, XcodeGen, UserNotifications, FileManager, NSStatusItem.

**Spec reference:** `docs/superpowers/specs/2026-05-27-hybrid-data-source-design.md`

---

## Conventions

- Every code task ends with a `git commit`. One logical change per commit.
- Tests live in `CCRateWidgetTests/` (introduced in Task 1) and use `XCTest`.
- When a step says "regenerate xcodeproj", run `xcodegen generate` from the repo root.
- Build verification command (used in many tasks):
  `xcodebuild build -project CCRateWidget.xcodeproj -scheme CCRateWidget -configuration Debug -destination 'platform=macOS' -quiet`
- Test verification command:
  `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet`
- Throughout, the App Group identifier is `group.com.dkkang.cc-rate-widget` (already declared in entitlements and `CredentialManager.appGroupID`).

---

## Task 1: Add `CCRateWidgetTests` target to project.yml

**Files:**
- Modify: `project.yml`
- Create: `CCRateWidgetTests/CCRateWidgetTests.swift`
- Create: `CCRateWidgetTests/Info.plist`

- [ ] **Step 1: Append the test target to `project.yml`**

Edit `project.yml` and append under `targets:` (after `RateWidgetExtension`):

```yaml
  CCRateWidgetTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: CCRateWidgetTests
      - path: Shared
    dependencies:
      - target: CCRateWidget
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.dkkang.cc-rate-widget.tests
        INFOPLIST_FILE: CCRateWidgetTests/Info.plist
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Claude Rate Widget.app/Contents/MacOS/Claude Rate Widget"
        BUNDLE_LOADER: "$(TEST_HOST)"
        ENABLE_APP_SANDBOX: false
        CODE_SIGN_ENTITLEMENTS: ""
        CODE_SIGNING_REQUIRED: false
        CODE_SIGN_IDENTITY: ""
        PROVISIONING_PROFILE_SPECIFIER: ""
```

- [ ] **Step 2: Create `CCRateWidgetTests/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
</dict>
</plist>
```

- [ ] **Step 3: Create a sanity test file**

`CCRateWidgetTests/CCRateWidgetTests.swift`:
```swift
import XCTest

final class SanityTests: XCTestCase {
    func test_sanity() {
        XCTAssertEqual(1 + 1, 2)
    }
}
```

- [ ] **Step 4: Regenerate xcodeproj and run tests**

Run: `xcodegen generate && xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet`
Expected: build succeeds, 1 test passes.

- [ ] **Step 5: Commit**

```bash
git add project.yml CCRateWidgetTests/
git commit -m "test: add CCRateWidgetTests unit test target"
```

---

## Task 2: Drop App Sandbox on the main app

**Files:**
- Modify: `project.yml:32`
- Modify: `CCRateWidget/CCRateWidget.entitlements`

- [ ] **Step 1: Flip `ENABLE_APP_SANDBOX` to false for `CCRateWidget` target**

In `project.yml`, under `targets.CCRateWidget.settings.base`, change:
```yaml
ENABLE_APP_SANDBOX: true
```
to:
```yaml
ENABLE_APP_SANDBOX: false
```
**Do not modify** `RateWidgetExtension`'s sandbox setting — it stays sandboxed.

- [ ] **Step 2: Remove sandbox key from entitlements**

Rewrite `CCRateWidget/CCRateWidget.entitlements` to:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.dkkang.cc-rate-widget</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 3: Regenerate xcodeproj and verify it builds**

Run: `xcodegen generate && xcodebuild build -project CCRateWidget.xcodeproj -scheme CCRateWidget -configuration Debug -destination 'platform=macOS' -quiet`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add project.yml CCRateWidget/CCRateWidget.entitlements
git commit -m "build: drop App Sandbox on main app to enable ~/.claude reads"
```

---

## Task 3: Extend `Models.swift` with new types

**Files:**
- Modify: `Shared/Models.swift`
- Create: `CCRateWidgetTests/ModelsTests.swift`

- [ ] **Step 1: Write the failing test**

`CCRateWidgetTests/ModelsTests.swift`:
```swift
import XCTest
@testable import Claude_Rate_Widget

final class ModelsTests: XCTestCase {
    func test_rateDataSource_rawValues() {
        XCTAssertEqual(RateDataSource.jsonl.rawValue, "jsonl")
        XCTAssertEqual(RateDataSource.oauth.rawValue, "oauth")
        XCTAssertEqual(RateDataSource.hybrid.rawValue, "hybrid")
        XCTAssertEqual(RateDataSource.partial.rawValue, "partial")
        XCTAssertEqual(RateDataSource.noLocalData.rawValue, "no_local_data")
    }

    func test_projectBreakdown_topN_returnsTop3SortedDescending() {
        let breakdown = ProjectBreakdown(entries: [
            .init(displayName: "a", path: "/a", tokens: 100, cost: 0.1),
            .init(displayName: "b", path: "/b", tokens: 500, cost: 0.5),
            .init(displayName: "c", path: "/c", tokens: 300, cost: 0.3),
            .init(displayName: "d", path: "/d", tokens: 50,  cost: 0.05),
        ])
        let top = breakdown.topN(3).map(\.displayName)
        XCTAssertEqual(top, ["b", "c", "a"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet -only-testing:CCRateWidgetTests/ModelsTests`
Expected: FAIL (`RateDataSource` and `ProjectBreakdown` not defined).

- [ ] **Step 3: Extend `Shared/Models.swift`**

Append these types to `Shared/Models.swift`:
```swift
// MARK: - Data Source

enum RateDataSource: String, Codable {
    case jsonl
    case oauth
    case hybrid
    case partial            // backfill in progress
    case noLocalData = "no_local_data"
}

// MARK: - Project Breakdown

struct ProjectBreakdown: Codable {
    struct Entry: Codable, Identifiable, Equatable {
        var id: String { path }
        let displayName: String
        let path: String          // raw cwd
        let tokens: Int
        let cost: Double          // USD
    }

    let entries: [Entry]
    var aliases: [String: String] = [:]   // cwd → user-chosen display name

    func topN(_ n: Int) -> [Entry] {
        entries.sorted(by: { $0.tokens > $1.tokens }).prefix(n).map { $0 }
    }
}

// MARK: - Inferred Limits

struct InferredLimits: Codable {
    /// nil when we don't yet have a confident estimate (learning state).
    var fiveHourTokens: Int? = nil
    var sevenDayTokens: Int? = nil
    var sevenDaySonnetTokens: Int? = nil

    /// Highest 7d-window total ever observed (for rolling 1.05× ratchet).
    var weeklyMaxObserved: Int = 0
    var fiveHourMaxObserved: Int = 0

    /// Optional cached values pulled from OAuth (when enabled).
    var officialFiveHourTokens: Int? = nil
    var officialSevenDayTokens: Int? = nil

    /// Manual user override; when non-nil, beats both P90 and official.
    var manualPlanTier: ManualPlanTier? = nil

    enum ManualPlanTier: String, Codable {
        case pro
        case max5
        case max20
    }
}
```

Also extend `RateData` and `OverallStatus`:

In `RateData`, add a stored property `source: RateDataSource` (after `status`). Update `static let placeholder` to pass `source: .jsonl`.

In `OverallStatus`, add the case `case noLocalData = "no_local_data"` and add to `label` switch: `case .noLocalData: return "No Local Data"`.

- [ ] **Step 4: Run tests to verify pass**

Run: `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet -only-testing:CCRateWidgetTests/ModelsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/Models.swift CCRateWidgetTests/ModelsTests.swift
git commit -m "feat(models): add RateDataSource, ProjectBreakdown, InferredLimits"
```

---

## Task 4: `Pricing.swift` — static cost table

**Files:**
- Create: `Shared/Pricing.swift`
- Create: `CCRateWidgetTests/PricingTests.swift`

- [ ] **Step 1: Write the failing test**

`CCRateWidgetTests/PricingTests.swift`:
```swift
import XCTest
@testable import Claude_Rate_Widget

final class PricingTests: XCTestCase {
    func test_opus47_cost_perMillion() {
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0)
        let cost = Pricing.cost(model: "claude-opus-4-7", usage: usage)
        // 15 + 75 = 90
        XCTAssertEqual(cost, 90.0, accuracy: 0.0001)
    }

    func test_sonnet46_cost_includesCacheWrite() {
        let usage = TokenUsage(input: 0, output: 0, cacheWrite: 1_000_000, cacheRead: 0)
        let cost = Pricing.cost(model: "claude-sonnet-4-6", usage: usage)
        XCTAssertEqual(cost, 3.75, accuracy: 0.0001)
    }

    func test_unknownModel_cost_isZero() {
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0)
        let cost = Pricing.cost(model: "claude-mystery-9-0", usage: usage)
        XCTAssertEqual(cost, 0)
    }

    func test_tokenSum_excludesCacheRead() {
        let usage = TokenUsage(input: 100, output: 50, cacheWrite: 25, cacheRead: 99999)
        XCTAssertEqual(usage.utilizationTokens, 175)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet -only-testing:CCRateWidgetTests/PricingTests`
Expected: FAIL (`Pricing`, `TokenUsage` not defined).

- [ ] **Step 3: Implement `Shared/Pricing.swift`**

```swift
import Foundation

struct TokenUsage: Equatable {
    let input: Int
    let output: Int
    let cacheWrite: Int        // cache_creation_input_tokens
    let cacheRead: Int         // cache_read_input_tokens

    /// Tokens that count toward utilization caps. Cache reads are essentially free.
    var utilizationTokens: Int { input + output + cacheWrite }
}

enum Pricing {
    /// $ per million tokens, by token bucket.
    private struct Rate {
        let input: Double
        let output: Double
        let cacheWrite: Double
        let cacheRead: Double
    }

    private static let rates: [(prefix: String, rate: Rate)] = [
        ("claude-opus-4",   Rate(input: 15.00, output: 75.00, cacheWrite: 18.75, cacheRead: 1.50)),
        ("claude-sonnet-4", Rate(input:  3.00, output: 15.00, cacheWrite:  3.75, cacheRead: 0.30)),
        ("claude-haiku-4",  Rate(input:  1.00, output:  5.00, cacheWrite:  1.25, cacheRead: 0.10)),
    ]

    static func cost(model: String, usage: TokenUsage) -> Double {
        guard let r = rates.first(where: { model.hasPrefix($0.prefix) })?.rate else { return 0 }
        return (Double(usage.input)      * r.input
              + Double(usage.output)     * r.output
              + Double(usage.cacheWrite) * r.cacheWrite
              + Double(usage.cacheRead)  * r.cacheRead) / 1_000_000.0
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet -only-testing:CCRateWidgetTests/PricingTests`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/Pricing.swift CCRateWidgetTests/PricingTests.swift
git commit -m "feat(pricing): add static Claude 4.x pricing table"
```

---

## Task 5: `AppGroupStore.swift` — atomic file-based snapshot store

**Files:**
- Create: `Shared/AppGroupStore.swift`
- Create: `CCRateWidgetTests/AppGroupStoreTests.swift`

- [ ] **Step 1: Write the failing test**

`CCRateWidgetTests/AppGroupStoreTests.swift`:
```swift
import XCTest
@testable import Claude_Rate_Widget

final class AppGroupStoreTests: XCTestCase {
    var tmpDir: URL!
    var store: AppGroupStore!

    override func setUp() {
        super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AppGroupStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = AppGroupStore(containerURL: tmpDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    func test_writeAndRead_limits_roundTrip() throws {
        let original = InferredLimits(
            fiveHourTokens: 100_000,
            sevenDayTokens: 500_000,
            sevenDaySonnetTokens: 250_000,
            weeklyMaxObserved: 400_000,
            fiveHourMaxObserved: 90_000,
            officialFiveHourTokens: nil,
            officialSevenDayTokens: nil,
            manualPlanTier: .max5
        )
        try store.writeLimits(original)
        let loaded = try store.readLimits()
        XCTAssertEqual(loaded?.fiveHourTokens, 100_000)
        XCTAssertEqual(loaded?.manualPlanTier, .max5)
    }

    func test_read_missingFile_returnsNil() throws {
        XCTAssertNil(try store.readLimits())
    }

    func test_read_corruptFile_throws() throws {
        let url = tmpDir.appendingPathComponent("limits.json")
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.readLimits())
    }

    func test_offsets_roundTrip() throws {
        try store.writeOffsets(["/a.jsonl": 100, "/b.jsonl": 250])
        let loaded = try store.readOffsets()
        XCTAssertEqual(loaded, ["/a.jsonl": 100, "/b.jsonl": 250])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet -only-testing:CCRateWidgetTests/AppGroupStoreTests`
Expected: FAIL.

- [ ] **Step 3: Implement `Shared/AppGroupStore.swift`**

```swift
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
```

- [ ] **Step 4: Run tests to verify pass**

Run: `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet -only-testing:CCRateWidgetTests/AppGroupStoreTests`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/AppGroupStore.swift CCRateWidgetTests/AppGroupStoreTests.swift
git commit -m "feat(store): add AppGroupStore for rate/projects/limits/offsets snapshots"
```

---

## Task 6: `JSONLEvent.swift` — single-line decoder

**Files:**
- Create: `Shared/JSONLEvent.swift`
- Create: `CCRateWidgetTests/JSONLEventTests.swift`
- Create: `CCRateWidgetTests/Fixtures/jsonl/assistant_one.jsonl`

- [ ] **Step 1: Add a fixture file**

`CCRateWidgetTests/Fixtures/jsonl/assistant_one.jsonl`:
```
{"type":"assistant","timestamp":"2026-05-27T08:14:22.103Z","sessionId":"abc","cwd":"/Users/dk/dev/proj","message":{"model":"claude-opus-4-7","usage":{"input_tokens":412,"cache_creation_input_tokens":1839,"cache_read_input_tokens":27431,"output_tokens":286}}}
{"type":"user","timestamp":"2026-05-27T08:14:22.000Z","sessionId":"abc"}
{"type":"assistant","timestamp":"2026-05-27T09:00:00.000Z","sessionId":"abc","cwd":"/Users/dk/dev/proj","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20}}}
not a json line
```

Make sure fixtures get bundled — they are picked up by the `path: CCRateWidgetTests` source entry. If the test target doesn't bundle the fixture, use `Bundle(for: type(of: self)).path(forResource:)` lookups or add a `resources:` block in `project.yml` for the test target.

- [ ] **Step 2: Write the failing test**

`CCRateWidgetTests/JSONLEventTests.swift`:
```swift
import XCTest
@testable import Claude_Rate_Widget

final class JSONLEventTests: XCTestCase {
    func test_decode_assistant_full() throws {
        let line = #"{"type":"assistant","timestamp":"2026-05-27T08:14:22.103Z","sessionId":"abc","cwd":"/Users/dk/dev/proj","message":{"model":"claude-opus-4-7","usage":{"input_tokens":412,"cache_creation_input_tokens":1839,"cache_read_input_tokens":27431,"output_tokens":286}}}"#
        let evt = try XCTUnwrap(JSONLEvent.decode(line: line))
        XCTAssertEqual(evt.cwd, "/Users/dk/dev/proj")
        XCTAssertEqual(evt.model, "claude-opus-4-7")
        XCTAssertEqual(evt.usage.input, 412)
        XCTAssertEqual(evt.usage.output, 286)
        XCTAssertEqual(evt.usage.cacheWrite, 1839)
        XCTAssertEqual(evt.usage.cacheRead, 27431)
    }

    func test_decode_userEvent_returnsNil() {
        let line = #"{"type":"user","timestamp":"2026-05-27T08:14:22.000Z","sessionId":"abc"}"#
        XCTAssertNil(JSONLEvent.decode(line: line))
    }

    func test_decode_corruptLine_returnsNil() {
        XCTAssertNil(JSONLEvent.decode(line: "not a json line"))
    }

    func test_decode_assistant_missingCacheFields_defaultsToZero() throws {
        let line = #"{"type":"assistant","timestamp":"2026-05-27T08:14:22.000Z","sessionId":"abc","cwd":"/p","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20}}}"#
        let evt = try XCTUnwrap(JSONLEvent.decode(line: line))
        XCTAssertEqual(evt.usage.cacheWrite, 0)
        XCTAssertEqual(evt.usage.cacheRead, 0)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet -only-testing:CCRateWidgetTests/JSONLEventTests`
Expected: FAIL.

- [ ] **Step 4: Implement `Shared/JSONLEvent.swift`**

```swift
import Foundation

struct JSONLEvent {
    let timestamp: Date
    let cwd: String
    let model: String
    let usage: TokenUsage

    static func decode(line: String) -> JSONLEvent? {
        guard let data = line.data(using: .utf8) else { return nil }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard (raw["type"] as? String) == "assistant" else { return nil }
        guard let ts = raw["timestamp"] as? String,
              let date = Self.iso.date(from: ts) else { return nil }
        guard let cwd = raw["cwd"] as? String else { return nil }
        guard let msg = raw["message"] as? [String: Any],
              let model = msg["model"] as? String,
              let usage = msg["usage"] as? [String: Any] else { return nil }
        let u = TokenUsage(
            input:      (usage["input_tokens"] as? Int) ?? 0,
            output:     (usage["output_tokens"] as? Int) ?? 0,
            cacheWrite: (usage["cache_creation_input_tokens"] as? Int) ?? 0,
            cacheRead:  (usage["cache_read_input_tokens"] as? Int) ?? 0
        )
        return JSONLEvent(timestamp: date, cwd: cwd, model: model, usage: u)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
```

If the formatter fails fractional-second parsing for a particular line, also try a no-fractions parse: add a second formatter without `.withFractionalSeconds` and try it as a fallback before returning nil.

- [ ] **Step 5: Run tests to verify pass**

Run: `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet -only-testing:CCRateWidgetTests/JSONLEventTests`
Expected: 4 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Shared/JSONLEvent.swift CCRateWidgetTests/JSONLEventTests.swift CCRateWidgetTests/Fixtures/
git commit -m "feat(jsonl): add JSONLEvent decoder for assistant lines"
```

---

## Task 7: `JSONLTailer.swift` — incremental file tail

**Files:**
- Create: `Shared/JSONLTailer.swift`
- Create: `CCRateWidgetTests/JSONLTailerTests.swift`

- [ ] **Step 1: Write the failing test**

`CCRateWidgetTests/JSONLTailerTests.swift`:
```swift
import XCTest
@testable import Claude_Rate_Widget

final class JSONLTailerTests: XCTestCase {
    var tmpFile: URL!

    override func setUp() {
        super.setUp()
        tmpFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tailer-\(UUID().uuidString).jsonl")
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpFile)
        super.tearDown()
    }

    private func write(_ s: String) {
        try? s.write(to: tmpFile, atomically: true, encoding: .utf8)
    }
    private func append(_ s: String) {
        guard let h = try? FileHandle(forWritingTo: tmpFile) else { return }
        try? h.seekToEnd()
        h.write(s.data(using: .utf8)!)
        try? h.close()
    }

    func test_firstReadFromZero_returnsAllLines_andAdvancesOffset() throws {
        write("a\nb\nc\n")
        let tailer = JSONLTailer(url: tmpFile)
        let (lines, newOffset) = try tailer.tail(from: 0)
        XCTAssertEqual(lines, ["a", "b", "c"])
        XCTAssertEqual(newOffset, 6)
    }

    func test_incrementalRead_returnsOnlyNewLines() throws {
        write("a\nb\n")
        let tailer = JSONLTailer(url: tmpFile)
        let (_, off1) = try tailer.tail(from: 0)
        append("c\nd\n")
        let (lines, off2) = try tailer.tail(from: off1)
        XCTAssertEqual(lines, ["c", "d"])
        XCTAssertGreaterThan(off2, off1)
    }

    func test_trailingPartialLine_isNotEmitted_offsetStaysAtLineStart() throws {
        write("a\nb\npartia")
        let tailer = JSONLTailer(url: tmpFile)
        let (lines, off) = try tailer.tail(from: 0)
        XCTAssertEqual(lines, ["a", "b"])
        XCTAssertEqual(off, 4)
        append("l\n")
        let (lines2, _) = try tailer.tail(from: off)
        XCTAssertEqual(lines2, ["partial"])
    }

    func test_fileShrunk_resetsOffsetAndRereads() throws {
        write("a\nb\nc\n")
        let tailer = JSONLTailer(url: tmpFile)
        _ = try tailer.tail(from: 0)
        write("x\n")
        let (lines, _) = try tailer.tail(from: 999)   // pretend cached offset > new size
        XCTAssertEqual(lines, ["x"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet -only-testing:CCRateWidgetTests/JSONLTailerTests`
Expected: FAIL.

- [ ] **Step 3: Implement `Shared/JSONLTailer.swift`**

```swift
import Foundation

struct JSONLTailer {
    let url: URL

    /// Reads complete lines starting at `offset`. Returns the lines (without trailing \n)
    /// and the new offset to persist. If the file is now smaller than `offset` (rotation /
    /// truncation), starts from 0.
    func tail(from offset: UInt64) throws -> (lines: [String], newOffset: UInt64) {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? UInt64) ?? 0
        var start = offset
        if start > size { start = 0 }
        if start == size { return ([], size) }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: start)
        let data = try handle.readToEnd() ?? Data()

        // Find last newline; everything after is a partial line we leave for next tick.
        guard let lastNewline = data.lastIndex(of: 0x0a) else {
            return ([], start)
        }
        let completeData = data.prefix(lastNewline + 1)
        let text = String(data: completeData, encoding: .utf8) ?? ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let newOffset = start + UInt64(completeData.count)
        return (lines, newOffset)
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet -only-testing:CCRateWidgetTests/JSONLTailerTests`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/JSONLTailer.swift CCRateWidgetTests/JSONLTailerTests.swift
git commit -m "feat(jsonl): add JSONLTailer for incremental byte-offset reads"
```

---

## Task 8: `JSONLAggregator.swift` — directory walk + window math

**Files:**
- Create: `Shared/JSONLAggregator.swift`
- Create: `CCRateWidgetTests/JSONLAggregatorTests.swift`

- [ ] **Step 1: Write the failing test**

`CCRateWidgetTests/JSONLAggregatorTests.swift`:
```swift
import XCTest
@testable import Claude_Rate_Widget

final class JSONLAggregatorTests: XCTestCase {
    var rootDir: URL!
    var storeDir: URL!
    var store: AppGroupStore!
    var aggregator: JSONLAggregator!

    override func setUp() {
        super.setUp()
        rootDir  = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("agg-root-\(UUID().uuidString)")
        storeDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("agg-store-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: rootDir,  withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        store = AppGroupStore(containerURL: storeDir)
        aggregator = JSONLAggregator(rootDir: rootDir, store: store)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: rootDir)
        try? FileManager.default.removeItem(at: storeDir)
        super.tearDown()
    }

    private func writeFile(_ relPath: String, _ contents: String) {
        let url = rootDir.appendingPathComponent(relPath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func assistantLine(ts: String, cwd: String, model: String, inTok: Int, outTok: Int) -> String {
        """
        {"type":"assistant","timestamp":"\(ts)","sessionId":"s","cwd":"\(cwd)","message":{"model":"\(model)","usage":{"input_tokens":\(inTok),"output_tokens":\(outTok)}}}
        """
    }

    func test_aggregate_singleFile_fiveHourWindow() throws {
        let now = Date()
        let inWindow  = ISO8601DateFormatter.shared.string(from: now.addingTimeInterval(-60))
        let outOfWindow = ISO8601DateFormatter.shared.string(from: now.addingTimeInterval(-6 * 3600))
        let lines = [
            assistantLine(ts: inWindow,    cwd: "/Users/dk/dev/a", model: "claude-opus-4-7",  inTok: 100, outTok: 50),
            assistantLine(ts: outOfWindow, cwd: "/Users/dk/dev/a", model: "claude-opus-4-7",  inTok: 999, outTok: 999),
        ].joined(separator: "\n") + "\n"
        writeFile("projA/session1.jsonl", lines)

        let snapshot = try aggregator.aggregate(now: now)
        XCTAssertEqual(snapshot.fiveHourTokens, 150)
    }

    func test_aggregate_corruptLine_skipped() throws {
        let now = Date()
        let good = assistantLine(ts: ISO8601DateFormatter.shared.string(from: now.addingTimeInterval(-60)),
                                  cwd: "/p", model: "claude-opus-4-7", inTok: 10, outTok: 20)
        writeFile("p/s.jsonl", "garbage\n" + good + "\n")
        let snap = try aggregator.aggregate(now: now)
        XCTAssertEqual(snap.fiveHourTokens, 30)
    }

    func test_aggregate_sonnetWindow_onlyCountsSonnet() throws {
        let now = Date()
        let ts = ISO8601DateFormatter.shared.string(from: now.addingTimeInterval(-3600))
        writeFile("p/s.jsonl",
            assistantLine(ts: ts, cwd: "/p", model: "claude-opus-4-7",  inTok: 100, outTok: 0) + "\n" +
            assistantLine(ts: ts, cwd: "/p", model: "claude-sonnet-4-6", inTok: 200, outTok: 0) + "\n")
        let snap = try aggregator.aggregate(now: now)
        XCTAssertEqual(snap.sevenDayTokens, 300)
        XCTAssertEqual(snap.sevenDaySonnetTokens, 200)
    }

    func test_aggregate_perProject_mergesAcrossFiles() throws {
        let now = Date()
        let ts = ISO8601DateFormatter.shared.string(from: now.addingTimeInterval(-60))
        writeFile("a/1.jsonl", assistantLine(ts: ts, cwd: "/Users/dk/dev/a", model: "claude-opus-4-7", inTok: 100, outTok: 0) + "\n")
        writeFile("a/2.jsonl", assistantLine(ts: ts, cwd: "/Users/dk/dev/a", model: "claude-opus-4-7", inTok: 50,  outTok: 0) + "\n")
        let snap = try aggregator.aggregate(now: now)
        let aEntry = snap.projects.entries.first { $0.path == "/Users/dk/dev/a" }
        XCTAssertEqual(aEntry?.tokens, 150)
    }
}

extension ISO8601DateFormatter {
    static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet -only-testing:CCRateWidgetTests/JSONLAggregatorTests`
Expected: FAIL.

- [ ] **Step 3: Implement `Shared/JSONLAggregator.swift`**

```swift
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
```

- [ ] **Step 4: Run tests to verify pass**

Run: `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet -only-testing:CCRateWidgetTests/JSONLAggregatorTests`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/JSONLAggregator.swift CCRateWidgetTests/JSONLAggregatorTests.swift
git commit -m "feat(jsonl): add JSONLAggregator for 5h/7d/sonnet windows and per-project totals"
```

---

## Task 9: `LimitInferrer.swift` — P90 + override precedence

**Files:**
- Create: `Shared/LimitInferrer.swift`
- Create: `CCRateWidgetTests/LimitInferrerTests.swift`

- [ ] **Step 1: Write the failing test**

`CCRateWidgetTests/LimitInferrerTests.swift`:
```swift
import XCTest
@testable import Claude_Rate_Widget

final class LimitInferrerTests: XCTestCase {
    func test_emptyHistory_returnsLearningState() {
        var limits = InferredLimits(weeklyMaxObserved: 0, fiveHourMaxObserved: 0)
        let result = LimitInferrer.infer(currentSnapshot: snap(),
                                         weeklySamples: [],
                                         fiveHourSamples: [],
                                         limits: &limits)
        XCTAssertNil(result.fiveHourTokens)
        XCTAssertNil(result.sevenDayTokens)
    }

    func test_weeklyMaxObserved_drivesRatchet() {
        var limits = InferredLimits(weeklyMaxObserved: 1_000_000, fiveHourMaxObserved: 100_000)
        let result = LimitInferrer.infer(currentSnapshot: snap(fiveH: 50_000, sevenD: 600_000),
                                         weeklySamples: [],
                                         fiveHourSamples: [],
                                         limits: &limits)
        // max(1_000_000 * 1.05, P90([]) * 1.2) → 1_050_000
        XCTAssertEqual(result.sevenDayTokens, 1_050_000)
    }

    func test_manualOverride_beatsP90() {
        var limits = InferredLimits(weeklyMaxObserved: 1_000_000,
                                    fiveHourMaxObserved: 100_000,
                                    manualPlanTier: .max20)
        let result = LimitInferrer.infer(currentSnapshot: snap(),
                                         weeklySamples: [10, 20, 30],
                                         fiveHourSamples: [],
                                         limits: &limits)
        XCTAssertEqual(result.sevenDayTokens, LimitInferrer.standardLimits[.max20]!.sevenDay)
    }

    func test_officialOAuth_beatsManualAndP90() {
        var limits = InferredLimits(weeklyMaxObserved: 1_000_000,
                                    fiveHourMaxObserved: 100_000,
                                    officialFiveHourTokens: 12345,
                                    officialSevenDayTokens: 67890,
                                    manualPlanTier: .max20)
        let result = LimitInferrer.infer(currentSnapshot: snap(),
                                         weeklySamples: [],
                                         fiveHourSamples: [],
                                         limits: &limits)
        XCTAssertEqual(result.fiveHourTokens, 12345)
        XCTAssertEqual(result.sevenDayTokens, 67890)
    }

    func test_currentSnapshot_above_weeklyMaxObserved_updatesObserved() {
        var limits = InferredLimits(weeklyMaxObserved: 1_000_000, fiveHourMaxObserved: 100_000)
        _ = LimitInferrer.infer(currentSnapshot: snap(fiveH: 0, sevenD: 1_500_000),
                                weeklySamples: [],
                                fiveHourSamples: [],
                                limits: &limits)
        XCTAssertEqual(limits.weeklyMaxObserved, 1_500_000)
    }

    private func snap(fiveH: Int = 0, sevenD: Int = 0) -> AggregationSnapshot {
        AggregationSnapshot(
            fiveHourTokens: fiveH, sevenDayTokens: sevenD, sevenDaySonnetTokens: 0,
            fiveHourCost: 0, sevenDayCost: 0,
            earliestInFiveHour: nil, earliestInSevenDay: nil,
            projects: ProjectBreakdown(entries: []),
            lastHalfHourTokensPerSecond: 0
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet -only-testing:CCRateWidgetTests/LimitInferrerTests`
Expected: FAIL.

- [ ] **Step 3: Implement `Shared/LimitInferrer.swift`**

```swift
import Foundation

enum LimitInferrer {
    struct StandardLimits {
        let fiveHour: Int
        let sevenDay: Int
    }

    /// Educated guesses for the standard plan tiers. Easy to bump as Anthropic publishes numbers.
    static let standardLimits: [InferredLimits.ManualPlanTier: StandardLimits] = [
        .pro:   StandardLimits(fiveHour:   200_000, sevenDay:   2_000_000),
        .max5:  StandardLimits(fiveHour: 1_000_000, sevenDay:  10_000_000),
        .max20: StandardLimits(fiveHour: 4_000_000, sevenDay:  40_000_000),
    ]

    struct Result {
        let fiveHourTokens: Int?
        let sevenDayTokens: Int?
        let sevenDaySonnetTokens: Int?
    }

    static func infer(
        currentSnapshot: AggregationSnapshot,
        weeklySamples: [Int],
        fiveHourSamples: [Int],
        limits: inout InferredLimits
    ) -> Result {
        // Ratchet observed maxes.
        if currentSnapshot.sevenDayTokens > limits.weeklyMaxObserved {
            limits.weeklyMaxObserved = currentSnapshot.sevenDayTokens
        }
        if currentSnapshot.fiveHourTokens > limits.fiveHourMaxObserved {
            limits.fiveHourMaxObserved = currentSnapshot.fiveHourTokens
        }

        // 1) Cached official from OAuth wins.
        if let f = limits.officialFiveHourTokens, let s = limits.officialSevenDayTokens {
            return Result(fiveHourTokens: f, sevenDayTokens: s, sevenDaySonnetTokens: s)
        }

        // 2) Manual override.
        if let tier = limits.manualPlanTier, let std = standardLimits[tier] {
            return Result(
                fiveHourTokens: std.fiveHour,
                sevenDayTokens: std.sevenDay,
                sevenDaySonnetTokens: std.sevenDay
            )
        }

        // 3) P90 + ratchet. Returns nil if we have neither observed-max nor samples (learning).
        let inferred5h = inferOne(samples: fiveHourSamples, observedMax: limits.fiveHourMaxObserved)
        let inferred7d = inferOne(samples: weeklySamples,   observedMax: limits.weeklyMaxObserved)

        return Result(
            fiveHourTokens: inferred5h,
            sevenDayTokens: inferred7d,
            sevenDaySonnetTokens: inferred7d
        )
    }

    private static func inferOne(samples: [Int], observedMax: Int) -> Int? {
        let ratchet = observedMax > 0 ? Int(Double(observedMax) * 1.05) : nil
        let p90 = percentile(samples, p: 0.90).map { Int(Double($0) * 1.2) }
        switch (ratchet, p90) {
        case let (.some(r), .some(p)): return max(r, p)
        case let (.some(r), .none):    return r
        case let (.none, .some(p)):    return p
        case (.none, .none):           return nil
        }
    }

    private static func percentile(_ samples: [Int], p: Double) -> Int? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let idx = max(0, min(sorted.count - 1, Int(Double(sorted.count - 1) * p)))
        return sorted[idx]
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet -only-testing:CCRateWidgetTests/LimitInferrerTests`
Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/LimitInferrer.swift CCRateWidgetTests/LimitInferrerTests.swift
git commit -m "feat(limits): add LimitInferrer with P90 + override precedence"
```

---

## Task 10: `AlertEngine.swift` — threshold + burn-rate forecast

**Files:**
- Create: `CCRateWidget/AlertEngine.swift`
- Create: `CCRateWidgetTests/AlertEngineTests.swift`

- [ ] **Step 1: Write the failing test**

`CCRateWidgetTests/AlertEngineTests.swift`:
```swift
import XCTest
@testable import Claude_Rate_Widget

final class AlertEngineTests: XCTestCase {
    func test_eightyCrossing_emitsAlert() {
        let prev = state(util: 0.79)
        let new  = state(util: 0.81)
        let alerts = AlertEngine.evaluate(prev: prev, new: new, now: Date())
        XCTAssertEqual(alerts.first?.kind, .threshold(0.80))
    }

    func test_eightyCrossing_doesNotRepeatSameWindow() {
        let prev = state(util: 0.81, lastThresholdFired: 0.80)
        let new  = state(util: 0.82, lastThresholdFired: 0.80)
        let alerts = AlertEngine.evaluate(prev: prev, new: new, now: Date())
        XCTAssertTrue(alerts.isEmpty)
    }

    func test_windowResetRearmsThreshold() {
        let resetTime = Date().addingTimeInterval(-60)
        let prev = state(util: 0.82, lastThresholdFired: 0.80, resetsAt: resetTime)
        let new  = state(util: 0.81, lastThresholdFired: nil,  resetsAt: resetTime.addingTimeInterval(3600))
        let alerts = AlertEngine.evaluate(prev: prev, new: new, now: Date())
        XCTAssertEqual(alerts.first?.kind, .threshold(0.80))
    }

    func test_forecast_etaUnderRemainingMinus30_emits() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(2 * 3600)             // 2h remaining
        // burn rate makes ETA = 30 min, remaining-30min = 90 min ⇒ ETA < 90 ⇒ fire
        let new = state(util: 0.50, resetsAt: resetsAt, burnTokensPerSec: 100, inferredLimit: 1_000_000)
        let alerts = AlertEngine.evaluate(prev: state(util: 0.50, resetsAt: resetsAt),
                                          new: new, now: now)
        XCTAssertTrue(alerts.contains { if case .forecast = $0.kind { return true } else { return false } })
    }

    func test_forecast_zeroBurn_doesNotEmit() {
        let now = Date()
        let new = state(util: 0.50, resetsAt: now.addingTimeInterval(3600),
                        burnTokensPerSec: 0, inferredLimit: 1_000_000)
        let alerts = AlertEngine.evaluate(prev: new, new: new, now: now)
        XCTAssertFalse(alerts.contains { if case .forecast = $0.kind { return true } else { return false } })
    }

    private func state(util: Double,
                       lastThresholdFired: Double? = nil,
                       resetsAt: Date? = nil,
                       burnTokensPerSec: Double = 0,
                       inferredLimit: Int = 1_000_000) -> AlertEngine.State {
        .init(
            utilization: util,
            resetsAt: resetsAt,
            lastThresholdFired: lastThresholdFired,
            forecastFiredAt: nil,
            burnTokensPerSec: burnTokensPerSec,
            inferredLimitTokens: inferredLimit,
            currentTokens: Int(Double(inferredLimit) * util)
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet -only-testing:CCRateWidgetTests/AlertEngineTests`
Expected: FAIL.

- [ ] **Step 3: Implement `CCRateWidget/AlertEngine.swift`**

```swift
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

enum AlertEngine {
    enum Kind: Equatable {
        case threshold(Double)              // 0.80 or 0.95
        case forecast(etaSeconds: Double)
    }
    struct Alert: Equatable {
        let kind: Kind
        let title: String
        let body: String
    }

    /// Inputs needed to decide; orchestrator builds these from snapshot + persisted state.
    struct State {
        var utilization: Double
        var resetsAt: Date?
        var lastThresholdFired: Double?     // 0.80 or 0.95 already fired for current window
        var forecastFiredAt: Date?          // already fired forecast for current window
        var burnTokensPerSec: Double
        var inferredLimitTokens: Int
        var currentTokens: Int
    }

    static func evaluate(prev: State, new: State, now: Date) -> [Alert] {
        var out: [Alert] = []

        let windowRolled = prev.resetsAt != new.resetsAt
        let armedThreshold = windowRolled ? nil : new.lastThresholdFired

        for threshold in [0.95, 0.80] {
            let alreadyFired = (armedThreshold ?? -1) >= threshold
            if !alreadyFired && new.utilization >= threshold {
                let pct = Int(threshold * 100)
                out.append(Alert(
                    kind: .threshold(threshold),
                    title: "Claude usage at \(pct)%",
                    body: "You've crossed \(pct)% of your inferred limit."
                ))
                break // only the highest crossed threshold per tick
            }
        }

        // Forecast: time to 100% at current burn rate.
        if new.burnTokensPerSec > 0,
           let resetsAt = new.resetsAt {
            let remainingTokens = max(0, new.inferredLimitTokens - new.currentTokens)
            let eta = Double(remainingTokens) / new.burnTokensPerSec
            let windowRemaining = resetsAt.timeIntervalSince(now)
            let didFireThisWindow = (prev.forecastFiredAt != nil) && !windowRolled
            if !didFireThisWindow && eta < windowRemaining - 1800 && eta > 0 {
                let minutes = Int(eta / 60)
                out.append(Alert(
                    kind: .forecast(etaSeconds: eta),
                    title: "Pace will hit limit",
                    body: "At current rate you'll hit 100% in ~\(minutes) min."
                ))
            }
        }
        return out
    }

    #if canImport(UserNotifications)
    static func deliver(_ alerts: [Alert]) {
        let center = UNUserNotificationCenter.current()
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            let req = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
            center.add(req, withCompletionHandler: nil)
        }
    }
    #endif
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet -only-testing:CCRateWidgetTests/AlertEngineTests`
Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add CCRateWidget/AlertEngine.swift CCRateWidgetTests/AlertEngineTests.swift
git commit -m "feat(alerts): add AlertEngine for thresholds and burn-rate forecast"
```

---

## Task 11: Rename `RateFetcher` → `OAuthClient` and demote to optional

**Files:**
- Move/Modify: `Shared/RateFetcher.swift` → `Shared/OAuthClient.swift`
- Modify: `Shared/Models.swift` (ensure `RateData.init` default `source` exists)

- [ ] **Step 1: Move and rename the file**

```bash
git mv Shared/RateFetcher.swift Shared/OAuthClient.swift
```

- [ ] **Step 2: Update class and API**

In `Shared/OAuthClient.swift`, change `final class RateFetcher` to `final class OAuthClient`; rename `static let shared` accordingly. Change the method signature:

```swift
struct OAuthLimits {
    let fiveHourTokens: Int?
    let sevenDayTokens: Int?
    let fiveHourResetsAt: Date?
    let sevenDayResetsAt: Date?
}

final class OAuthClient {
    static let shared = OAuthClient()
    private init() {}

    /// Returns nil on any failure (including disabled, unauthorized, forbidden).
    /// Caller treats nil as "not available" — no error UI flashes from this path.
    func fetchOfficialLimits() async -> OAuthLimits? {
        // ... existing logic, but rather than producing RateData,
        //     extract utilization * a heuristic to convert to tokens? No — we cannot.
        //     The OAuth /usage endpoint returns utilization %, not token counts.
        //     Instead, return nil here for 1.7 and let LimitInferrer fall back to P90.
        //     Future: pair OAuth utilization with our locally-measured tokens to
        //     derive the actual limit; deferred to 1.8.
        return nil
    }
}
```

Per the spec, in 1.7 the OAuth client compiles but produces no usable limit numbers (the `/usage` endpoint reports percentages, not absolute tokens). Keep all credential / refresh / status-code logic intact — it's reused unchanged when 1.8 introduces the "derive absolute limits from utilization × current consumption" trick. The point of Task 11 is purely: **stop calling `RateFetcher` from any data path so OAuth is no longer required to ship a build.**

Also delete the legacy `OverallStatus` `unauthorized`/`forbidden` short-circuits from any *new* paths — `OAuthClient` is now silent on failure.

- [ ] **Step 3: Remove the old call site**

Search for `RateFetcher` and `RateFetcher.shared` in the codebase:
`grep -rn "RateFetcher" .`
Replace any production references with `OAuthClient.shared`. (Existing call sites in `RateProvider.swift` and `ContentView.swift` will be rewritten end-to-end in later tasks; for now, change them only enough to compile against the renamed class with no behavior change.)

- [ ] **Step 4: Build to verify**

Run: `xcodegen generate && xcodebuild build -project CCRateWidget.xcodeproj -scheme CCRateWidget -configuration Debug -destination 'platform=macOS' -quiet`
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Shared/OAuthClient.swift CCRateWidget/ContentView.swift RateWidgetExtension/RateProvider.swift
git commit -m "refactor: rename RateFetcher → OAuthClient and demote to optional"
```

---

## Task 12: `AggregationCoordinator.swift` — timer-driven orchestration

**Files:**
- Create: `CCRateWidget/AggregationCoordinator.swift`

- [ ] **Step 1: Implement the coordinator**

```swift
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
        runOnce()
        timer?.invalidate()
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

    private func tick() throws -> RateData {
        let store = AppGroupStore.shared
        let root  = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)

        guard FileManager.default.fileExists(atPath: root.path) else {
            let r = RateData(
                session:      CategoryData(utilization: 0, resetsAt: nil),
                weekly:       CategoryData(utilization: 0, resetsAt: nil),
                weeklySonnet: CategoryData(utilization: 0, resetsAt: nil),
                overage:      OverageData(isEnabled: false, utilization: 0, spent: 0, limit: 0),
                fetchedAt: Date(),
                status: .noLocalData,
                source: .noLocalData
            )
            try store.writeRate(r)
            return r
        }

        let aggregator = JSONLAggregator(rootDir: root, store: store)
        let snap = try aggregator.aggregate(now: Date())
        var limits = (try store.readLimits()) ?? InferredLimits(weeklyMaxObserved: 0,
                                                                fiveHourMaxObserved: 0)
        let inferred = LimitInferrer.infer(
            currentSnapshot: snap,
            weeklySamples: [],          // sample history wiring lands in Task 19 (backfill)
            fiveHourSamples: [],
            limits: &limits
        )
        try store.writeLimits(limits)
        try store.writeProjects(snap.projects)

        let now = Date()
        func cat(tokens: Int, limit: Int?, earliest: Date?, window: TimeInterval) -> CategoryData {
            let utilization: Double
            if let limit, limit > 0 {
                utilization = Double(tokens) / Double(limit)
            } else {
                utilization = 0
            }
            let resetsAt = earliest.map { $0.addingTimeInterval(window) }
            return CategoryData(utilization: utilization, resetsAt: resetsAt)
        }

        let session  = cat(tokens: snap.fiveHourTokens, limit: inferred.fiveHourTokens,
                           earliest: snap.earliestInFiveHour, window: 5 * 3600)
        let weekly   = cat(tokens: snap.sevenDayTokens, limit: inferred.sevenDayTokens,
                           earliest: snap.earliestInSevenDay, window: 7 * 86400)
        let sonnet   = cat(tokens: snap.sevenDaySonnetTokens, limit: inferred.sevenDaySonnetTokens,
                           earliest: snap.earliestInSevenDay, window: 7 * 86400)

        let maxUtil = max(session.utilization, weekly.utilization)
        let status: OverallStatus = maxUtil >= 1.0 ? .rateLimited
                                    : maxUtil >= 0.80 ? .warning
                                    : .active

        let source: RateDataSource = (inferred.sevenDayTokens == nil) ? .partial : .jsonl
        let rate = RateData(
            session: session,
            weekly: weekly,
            weeklySonnet: sonnet,
            overage: OverageData(isEnabled: false, utilization: 0, spent: 0, limit: 0),
            fetchedAt: now,
            status: status,
            source: source
        )

        try store.writeRate(rate)

        // Alert pass.
        let prevState: AlertEngine.State
        if let prev = try store.readRate() {
            prevState = AlertEngine.State(
                utilization: max(prev.session.utilization, prev.weekly.utilization),
                resetsAt: prev.weekly.resetsAt,
                lastThresholdFired: nil,      // persistence of fire-state added in Task 13
                forecastFiredAt: nil,
                burnTokensPerSec: 0,
                inferredLimitTokens: inferred.sevenDayTokens ?? 0,
                currentTokens: snap.sevenDayTokens
            )
        } else {
            prevState = AlertEngine.State(utilization: 0, resetsAt: nil,
                                          lastThresholdFired: nil, forecastFiredAt: nil,
                                          burnTokensPerSec: 0,
                                          inferredLimitTokens: 0, currentTokens: 0)
        }
        let newState = AlertEngine.State(
            utilization: maxUtil,
            resetsAt: rate.weekly.resetsAt,
            lastThresholdFired: nil,
            forecastFiredAt: nil,
            burnTokensPerSec: snap.lastHalfHourTokensPerSecond,
            inferredLimitTokens: inferred.sevenDayTokens ?? 0,
            currentTokens: snap.sevenDayTokens
        )
        let alerts = AlertEngine.evaluate(prev: prevState, new: newState, now: now)
        AlertEngine.deliver(alerts)

        return rate
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodegen generate && xcodebuild build -project CCRateWidget.xcodeproj -scheme CCRateWidget -configuration Debug -destination 'platform=macOS' -quiet`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add CCRateWidget/AggregationCoordinator.swift
git commit -m "feat(coordinator): add AggregationCoordinator timer + tick orchestration"
```

---

## Task 13: Persist alert-engine fire-state across ticks

**Files:**
- Modify: `Shared/AppGroupStore.swift`
- Modify: `CCRateWidget/AggregationCoordinator.swift`
- Create: `CCRateWidgetTests/AlertStateRoundTripTests.swift`

- [ ] **Step 1: Add an `AlertState` persistence type**

In `Shared/AppGroupStore.swift`, add:
```swift
struct AlertState: Codable {
    var lastThresholdFired: Double?
    var forecastFiredAt: Double?
    var windowResetsAt: Double?
}

extension AppGroupStore {
    private var alertStateURL: URL { containerURL.appendingPathComponent("alert_state.json") }
    func readAlertState() throws -> AlertState? { try read(alertStateURL, as: AlertState.self) }
    func writeAlertState(_ value: AlertState) throws { try atomicWrite(value, to: alertStateURL) }
}
```

(Note: `read`/`atomicWrite` are private; make a `fileprivate` re-export or move them to `internal` for the extension to compile.)

- [ ] **Step 2: Write the round-trip test**

`CCRateWidgetTests/AlertStateRoundTripTests.swift`:
```swift
import XCTest
@testable import Claude_Rate_Widget

final class AlertStateRoundTripTests: XCTestCase {
    func test_alertState_roundTrip() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alerts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = AppGroupStore(containerURL: dir)
        let s = AlertState(lastThresholdFired: 0.80,
                           forecastFiredAt: Date().timeIntervalSince1970,
                           windowResetsAt: Date().timeIntervalSince1970 + 3600)
        try store.writeAlertState(s)
        let loaded = try XCTUnwrap(store.readAlertState())
        XCTAssertEqual(loaded.lastThresholdFired, 0.80)
        try FileManager.default.removeItem(at: dir)
    }
}
```

- [ ] **Step 3: Run test to verify pass after stub**

Run: `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet -only-testing:CCRateWidgetTests/AlertStateRoundTripTests`
Expected: PASS.

- [ ] **Step 4: Wire fire-state in `AggregationCoordinator.tick()`**

Replace the temporary `prevState` / `newState` blocks with:

```swift
let storedAlert = (try? store.readAlertState()) ?? AlertState(lastThresholdFired: nil,
                                                              forecastFiredAt: nil,
                                                              windowResetsAt: nil)
let prevState = AlertEngine.State(
    utilization: storedAlert.lastThresholdFired ?? 0,
    resetsAt: storedAlert.windowResetsAt.map(Date.init(timeIntervalSince1970:)),
    lastThresholdFired: storedAlert.lastThresholdFired,
    forecastFiredAt: storedAlert.forecastFiredAt.map(Date.init(timeIntervalSince1970:)),
    burnTokensPerSec: 0,
    inferredLimitTokens: inferred.sevenDayTokens ?? 0,
    currentTokens: snap.sevenDayTokens
)
let newState = AlertEngine.State(
    utilization: maxUtil,
    resetsAt: rate.weekly.resetsAt,
    lastThresholdFired: storedAlert.lastThresholdFired,
    forecastFiredAt: storedAlert.forecastFiredAt.map(Date.init(timeIntervalSince1970:)),
    burnTokensPerSec: snap.lastHalfHourTokensPerSecond,
    inferredLimitTokens: inferred.sevenDayTokens ?? 0,
    currentTokens: snap.sevenDayTokens
)
let alerts = AlertEngine.evaluate(prev: prevState, new: newState, now: now)
AlertEngine.deliver(alerts)

// Persist updated fire-state.
var nextAlert = storedAlert
if rate.weekly.resetsAt?.timeIntervalSince1970 != storedAlert.windowResetsAt {
    nextAlert.lastThresholdFired = nil
    nextAlert.forecastFiredAt = nil
    nextAlert.windowResetsAt = rate.weekly.resetsAt?.timeIntervalSince1970
}
for alert in alerts {
    switch alert.kind {
    case .threshold(let t):    nextAlert.lastThresholdFired = max(nextAlert.lastThresholdFired ?? 0, t)
    case .forecast:            nextAlert.forecastFiredAt = now.timeIntervalSince1970
    }
}
try? store.writeAlertState(nextAlert)
```

- [ ] **Step 5: Build to verify**

Run: `xcodegen generate && xcodebuild build -project CCRateWidget.xcodeproj -scheme CCRateWidget -configuration Debug -destination 'platform=macOS' -quiet`
Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Shared/AppGroupStore.swift CCRateWidget/AggregationCoordinator.swift CCRateWidgetTests/AlertStateRoundTripTests.swift
git commit -m "feat(alerts): persist alert fire-state across coordinator ticks"
```

---

## Task 14: Update widget `RateProvider` to read from `AppGroupStore`

**Files:**
- Modify: `RateWidgetExtension/RateProvider.swift`

- [ ] **Step 1: Replace the body of `RateProvider`**

Rewrite `RateWidgetExtension/RateProvider.swift` to:

```swift
import WidgetKit

struct RateEntry: TimelineEntry {
    let date: Date
    let data: RateData
    let projects: ProjectBreakdown?
}

struct RateProvider: TimelineProvider {
    func placeholder(in context: Context) -> RateEntry {
        RateEntry(date: Date(), data: .placeholder, projects: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (RateEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RateEntry>) -> Void) {
        let entry = load()
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func load() -> RateEntry {
        let store = AppGroupStore.shared
        let data = (try? store.readRate()) ?? .placeholder
        let projects = try? store.readProjects()
        return RateEntry(date: Date(), data: data, projects: projects)
    }
}
```

Delete any remaining `RateFetcher`/`OAuthClient` calls from this file — the widget no longer fetches.

- [ ] **Step 2: Build & smoke**

Run: `xcodegen generate && xcodebuild build -project CCRateWidget.xcodeproj -scheme CCRateWidget -configuration Debug -destination 'platform=macOS' -quiet`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add RateWidgetExtension/RateProvider.swift
git commit -m "refactor(widget): RateProvider reads from AppGroupStore, no network"
```

---

## Task 15: Large widget — Top 3 project strip + source indicator

**Files:**
- Modify: `RateWidgetExtension/RateWidgetViews.swift`
- Modify: `RateWidgetExtension/RateWidget.swift`

- [ ] **Step 1: Add source indicator to all three views**

Open `RateWidgetExtension/RateWidgetViews.swift`. For each of `SmallRateView`, `MediumRateView`, `LargeRateView`, add a small badge in a corner:

```swift
private struct SourceBadge: View {
    let source: RateDataSource
    var body: some View {
        Text(label)
            .font(.system(size: 8, weight: .semibold))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.25)))
            .foregroundStyle(color)
            .accessibilityLabel("Data source: \(label)")
    }
    private var label: String {
        switch source {
        case .jsonl: return "LOCAL"
        case .oauth: return "OAUTH"
        case .hybrid: return "HYBRID"
        case .partial: return "LEARNING"
        case .noLocalData: return "SETUP"
        }
    }
    private var color: Color {
        switch source {
        case .jsonl:     return .secondary
        case .oauth:     return .blue
        case .hybrid:    return .green
        case .partial:   return .orange
        case .noLocalData: return .red
        }
    }
}
```

Use `SourceBadge(source: entry.data.source)` overlaid at the top-trailing corner of each view (`.overlay(alignment: .topTrailing) { SourceBadge(...) .padding(6) }`).

- [ ] **Step 2: Add Top 3 project strip to LargeRateView**

Add a sub-view to `RateWidgetViews.swift`:

```swift
struct LargeProjectStrip: View {
    let projects: ProjectBreakdown
    var body: some View {
        let top = projects.topN(3)
        VStack(alignment: .leading, spacing: 4) {
            Text("Top projects")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(top) { entry in
                HStack {
                    Text(entry.displayName)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("\(entry.tokens / 1000)k")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if top.isEmpty {
                Text("No activity yet")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
```

Embed it at the bottom of `LargeRateView`'s body, separated by a `Divider()`. The provider already passes `entry.projects` through.

- [ ] **Step 3: Pass projects to LargeRateView**

In `RateWidget.swift`, update the entry-view body switch to pass `entry.projects` into the Large variant. Update the Large variant initializer to accept it.

- [ ] **Step 4: Manual visual check**

Run: `xcodegen generate && xcodebuild build -project CCRateWidget.xcodeproj -scheme CCRateWidget -configuration Debug -destination 'platform=macOS' -quiet`
Build the app, open the widget gallery, verify Large variant renders Top 3 with badges. (Document the result in commit message if smoke is good.)

- [ ] **Step 5: Commit**

```bash
git add RateWidgetExtension/RateWidgetViews.swift RateWidgetExtension/RateWidget.swift
git commit -m "feat(widget): Large variant Top-3 projects + source indicator"
```

---

## Task 16: Main app — Settings store and view

**Files:**
- Create: `CCRateWidget/SettingsStore.swift`
- Create: `CCRateWidget/SettingsView.swift`

- [ ] **Step 1: Implement `SettingsStore`**

```swift
import Foundation
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var oauthEnabled: Bool {
        didSet { defaults.set(oauthEnabled, forKey: "oauthEnabled") }
    }
    @Published var menuBarEnabled: Bool {
        didSet { defaults.set(menuBarEnabled, forKey: "menuBarEnabled") }
    }
    @Published var manualPlanTier: String {
        didSet { defaults.set(manualPlanTier, forKey: "manualPlanTier") }
    }

    private let defaults: UserDefaults
    private init() {
        self.defaults = UserDefaults(suiteName: "group.com.dkkang.cc-rate-widget") ?? .standard
        self.oauthEnabled = defaults.bool(forKey: "oauthEnabled")              // default false
        self.menuBarEnabled = defaults.bool(forKey: "menuBarEnabled")          // default false
        self.manualPlanTier = defaults.string(forKey: "manualPlanTier") ?? "auto"
    }
}
```

- [ ] **Step 2: Implement `SettingsView`**

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store = SettingsStore.shared
    @State private var showRelaunchPrompt = false

    var body: some View {
        Form {
            Section("Plan tier") {
                Picker("Plan", selection: $store.manualPlanTier) {
                    Text("Auto (P90)").tag("auto")
                    Text("Pro").tag("pro")
                    Text("Max5").tag("max5")
                    Text("Max20").tag("max20")
                }
                .pickerStyle(.menu)
                .onChange(of: store.manualPlanTier) { _, new in
                    persistManualTier(new)
                }
                Text("Choose the tier that matches your subscription, or leave on Auto to let the widget estimate from your usage history.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Background") {
                Toggle("Run in menu bar (recommended for alerts)", isOn: $store.menuBarEnabled)
                    .onChange(of: store.menuBarEnabled) { _, _ in showRelaunchPrompt = true }
                Text("Required for notifications to fire even when the main window is closed.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Anthropic OAuth (optional)") {
                Toggle("Pull official quota when available", isOn: $store.oauthEnabled)
                Text("Off by default. Anthropic's terms discourage third-party OAuth use; enabling places that responsibility on you.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Data") {
                Button("Re-prompt for ~/.claude access") {
                    HomeAccessPrompter.shared.prompt()
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .alert("Restart required", isPresented: $showRelaunchPrompt) {
            Button("Quit and reopen") { NSApp.relaunch() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Menu bar mode requires a restart to apply.")
        }
    }

    private func persistManualTier(_ raw: String) {
        var limits = (try? AppGroupStore.shared.readLimits())
            ?? InferredLimits(weeklyMaxObserved: 0, fiveHourMaxObserved: 0)
        switch raw {
        case "pro":   limits.manualPlanTier = .pro
        case "max5":  limits.manualPlanTier = .max5
        case "max20": limits.manualPlanTier = .max20
        default:      limits.manualPlanTier = nil
        }
        try? AppGroupStore.shared.writeLimits(limits)
        AggregationCoordinator.shared.runOnce()
    }
}

extension NSApplication {
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
```

`HomeAccessPrompter` is implemented in Task 17.

- [ ] **Step 3: Build to verify**

Run: `xcodegen generate && xcodebuild build -project CCRateWidget.xcodeproj -scheme CCRateWidget -configuration Debug -destination 'platform=macOS' -quiet`
Expected: build succeeds (with the `HomeAccessPrompter` reference unresolved if Task 17 not yet done — in which case stub it: `final class HomeAccessPrompter { static let shared = HomeAccessPrompter(); func prompt() {} }` in this same file, to be replaced in Task 17).

- [ ] **Step 4: Commit**

```bash
git add CCRateWidget/SettingsStore.swift CCRateWidget/SettingsView.swift
git commit -m "feat(app): add SettingsStore and SettingsView for tier, menu bar, OAuth"
```

---

## Task 17: Main app — `HomeAccessPrompter` for `~/.claude/` access

**Files:**
- Create: `CCRateWidget/HomeAccessPrompter.swift`

- [ ] **Step 1: Implement the prompter**

```swift
import AppKit

final class HomeAccessPrompter {
    static let shared = HomeAccessPrompter()
    private init() {}

    /// Open NSOpenPanel pinned to ~/.claude/projects to trigger a TCC prompt.
    /// User selects the folder; we hold a security-scoped bookmark not strictly
    /// needed (sandbox is off) but the panel surface itself is what nudges TCC.
    func prompt() {
        let panel = NSOpenPanel()
        panel.message = "Select your ~/.claude/projects folder to allow Claude Rate Widget to read usage data."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        let home = FileManager.default.homeDirectoryForCurrentUser
        panel.directoryURL = home.appendingPathComponent(".claude/projects")
        panel.showsHiddenFiles = true
        panel.begin { _ in
            AggregationCoordinator.shared.runOnce()
        }
    }
}
```

Replace the stub in `SettingsView.swift` (if any) with this real implementation by deleting the stub.

- [ ] **Step 2: Build to verify**

Run: `xcodegen generate && xcodebuild build -project CCRateWidget.xcodeproj -scheme CCRateWidget -configuration Debug -destination 'platform=macOS' -quiet`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add CCRateWidget/HomeAccessPrompter.swift CCRateWidget/SettingsView.swift
git commit -m "feat(app): add HomeAccessPrompter for ~/.claude access re-prompt"
```

---

## Task 18: Main app — Project list view + dashboard

**Files:**
- Modify: `CCRateWidget/ContentView.swift`

- [ ] **Step 1: Rewrite `ContentView`**

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var coordinator = AggregationCoordinator.shared
    @State private var projects: ProjectBreakdown?
    @State private var tab: Tab = .dashboard

    enum Tab: String, CaseIterable { case dashboard = "Dashboard", projects = "Projects", settings = "Settings" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).padding()

            Divider()
            Group {
                switch tab {
                case .dashboard: DashboardSection(rate: coordinator.lastSnapshot)
                case .projects:  ProjectsSection(projects: projects)
                case .settings:  SettingsView()
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 520, minHeight: 420)
        .task {
            coordinator.start()
            refreshProjects()
        }
        .onReceive(coordinator.$lastSnapshot) { _ in refreshProjects() }
    }

    private func refreshProjects() {
        projects = try? AppGroupStore.shared.readProjects()
    }
}

private struct DashboardSection: View {
    let rate: RateData?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if rate?.status == .noLocalData {
                SetupGuide()
            } else if let rate {
                LimitRow(label: "5-hour session", cat: rate.session)
                LimitRow(label: "7-day",           cat: rate.weekly)
                LimitRow(label: "7-day Sonnet",    cat: rate.weeklySonnet)
                Text("Source: \(rate.source.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView("Loading…")
            }
        }
        .padding()
    }
}

private struct LimitRow: View {
    let label: String
    let cat: CategoryData
    var body: some View {
        VStack(alignment: .leading) {
            Text(label).font(.headline)
            ProgressView(value: min(cat.utilization, 1.0))
            HStack {
                Text("\(Int(cat.utilization * 100))%")
                Spacer()
                if let resetsAt = cat.resetsAt {
                    Text("resets \(resetsAt, style: .relative)")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ProjectsSection: View {
    let projects: ProjectBreakdown?
    var body: some View {
        Group {
            if let projects, !projects.entries.isEmpty {
                List(projects.topN(20)) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.displayName).font(.body)
                            Text(entry.path).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(entry.tokens / 1000)k tok").monospacedDigit()
                            Text(String(format: "$%.2f", entry.cost))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("No project activity in current windows.")
                    .foregroundStyle(.secondary).padding()
            }
        }
    }
}

private struct SetupGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setup required").font(.title2.bold())
            Text("Claude Rate Widget reads ~/.claude/projects/ on this Mac to compute your usage. We'll request permission once.")
            Button("Grant access") { HomeAccessPrompter.shared.prompt() }
        }.padding()
    }
}
```

- [ ] **Step 2: Build and smoke**

Run: `xcodegen generate && xcodebuild build -project CCRateWidget.xcodeproj -scheme CCRateWidget -configuration Debug -destination 'platform=macOS' -quiet`

Launch the app:
`open ~/Library/Developer/Xcode/DerivedData/CCRateWidget-*/Build/Products/Debug/Claude\ Rate\ Widget.app`

Verify: the three tabs render; Dashboard shows progress bars; Projects shows non-empty list (assuming you've used Claude Code at least once).

- [ ] **Step 3: Commit**

```bash
git add CCRateWidget/ContentView.swift
git commit -m "feat(app): rewrite ContentView with Dashboard/Projects/Settings tabs"
```

---

## Task 19: Background backfill of 6 weeks of weekly samples

**Files:**
- Create: `CCRateWidget/Backfill.swift`
- Modify: `CCRateWidget/AggregationCoordinator.swift`

- [ ] **Step 1: Implement backfill**

```swift
import Foundation

/// Walks ~/.claude/projects once on first launch to build a 6-week history
/// of weekly token totals (one bucket per UTC midnight). Persisted into limits.json
/// via the `weeklySamples` field added below.
enum Backfill {
    static let weeksBack = 6
    private static let didRunKey = "backfill_didRun_v1"

    static var didRun: Bool {
        UserDefaults.standard.bool(forKey: didRunKey)
    }

    static func runIfNeeded(rootDir: URL, store: AppGroupStore) {
        guard !didRun else { return }
        Task.detached(priority: .background) {
            do {
                let samples = try buildWeeklySamples(rootDir: rootDir)
                var limits = (try? store.readLimits()) ?? InferredLimits(weeklyMaxObserved: 0,
                                                                          fiveHourMaxObserved: 0)
                limits.weeklySamples = samples
                try store.writeLimits(limits)
                UserDefaults.standard.set(true, forKey: didRunKey)
                await MainActor.run { AggregationCoordinator.shared.runOnce() }
            } catch {
                NSLog("[Backfill] failed: \(error)")
            }
        }
    }

    private static func buildWeeklySamples(rootDir: URL) throws -> [Int] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: rootDir,
                                             includingPropertiesForKeys: [.isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else { return [] }
        let now = Date()
        let cutoff = now.addingTimeInterval(-TimeInterval(weeksBack) * 7 * 86400)
        var weekTotals: [Int: Int] = [:]   // weekIndexFromNow → tokens

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let evt = JSONLEvent.decode(line: String(line)) else { continue }
                if evt.timestamp < cutoff { continue }
                let weekIdx = Int(now.timeIntervalSince(evt.timestamp) / (7 * 86400))
                weekTotals[weekIdx, default: 0] += evt.usage.utilizationTokens
            }
        }
        return (0..<weeksBack).map { weekTotals[$0] ?? 0 }
    }
}
```

- [ ] **Step 2: Extend `InferredLimits` with `weeklySamples`**

In `Shared/Models.swift`, add to `InferredLimits`:
```swift
var weeklySamples: [Int] = []
var fiveHourSamples: [Int] = []
```

Update test fixtures in `LimitInferrerTests.swift` calls if they break.

- [ ] **Step 3: Use samples in coordinator's `tick()`**

Replace the `weeklySamples: []` / `fiveHourSamples: []` arguments in `AggregationCoordinator.tick()` with the persisted samples from `limits.weeklySamples` / `limits.fiveHourSamples`. Add `Backfill.runIfNeeded(rootDir: root, store: store)` near the top of `tick()` (right after the existence check).

- [ ] **Step 4: Build to verify**

Run: `xcodegen generate && xcodebuild build -project CCRateWidget.xcodeproj -scheme CCRateWidget -configuration Debug -destination 'platform=macOS' -quiet`
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add CCRateWidget/Backfill.swift Shared/Models.swift CCRateWidget/AggregationCoordinator.swift
git commit -m "feat(history): one-time 6-week backfill of weekly samples"
```

---

## Task 20: `MenuBarMode.swift` — opt-in status item

**Files:**
- Create: `CCRateWidget/MenuBarMode.swift`
- Modify: `CCRateWidget/CCRateWidgetApp.swift`
- Modify: `CCRateWidget/Info.plist`

- [ ] **Step 1: Add `LSUIElement` toggle to `Info.plist`**

Add to `CCRateWidget/Info.plist`:
```xml
<key>LSUIElement</key>
<false/>
```
(Default false. We toggle it programmatically by relaunching with a transient override via `defaults write`. Documented in step 4 below.)

- [ ] **Step 2: Implement `MenuBarMode`**

```swift
import AppKit
import SwiftUI

@MainActor
final class MenuBarMode: ObservableObject {
    static let shared = MenuBarMode()
    private var statusItem: NSStatusItem?

    func installIfEnabled() {
        guard SettingsStore.shared.menuBarEnabled else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "CC"
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh now", action: #selector(refresh), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open main window", action: #selector(open), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func refresh() {
        AggregationCoordinator.shared.runOnce()
    }
    @objc private func open() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first { window.makeKeyAndOrderFront(nil) }
    }
    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
```

- [ ] **Step 3: Wire app start in `CCRateWidgetApp.swift`**

Replace `CCRateWidget/CCRateWidgetApp.swift`:

```swift
import SwiftUI

@main
struct CCRateWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Claude Rate Widget", id: "main") {
            ContentView()
                .task { await requestNotificationsIfNeeded() }
        }
        .defaultSize(width: 560, height: 440)
    }

    private func requestNotificationsIfNeeded() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        #endif
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AggregationCoordinator.shared.start()
        MenuBarMode.shared.installIfEnabled()
    }
}
```

- [ ] **Step 4: Document LSUIElement runtime toggle**

In `SettingsView.swift`'s `showRelaunchPrompt` handler, before relaunch, persist a hint so the next launch knows to enable menu-bar mode. Since `LSUIElement` is plist-bound and cannot be changed at runtime, document this limitation in the relaunch alert text: replace the message with:

```swift
Text("Menu bar mode setting saved. The Dock icon will remain visible — relaunching is only needed to attach the menu-bar item this session.")
```

(For 1.7, both Dock icon and menu-bar item coexist when menu-bar mode is on. Hiding the Dock icon entirely is deferred — it requires shipping a second target or a launchctl-based helper.)

- [ ] **Step 5: Build to verify and smoke**

Run: `xcodegen generate && xcodebuild build -project CCRateWidget.xcodeproj -scheme CCRateWidget -configuration Debug -destination 'platform=macOS' -quiet`

Launch app. Toggle "Run in menu bar" on. Relaunch (or invoke "Quit and reopen" alert button). Verify a status-bar "CC" item appears with the three menu options.

- [ ] **Step 6: Commit**

```bash
git add CCRateWidget/MenuBarMode.swift CCRateWidget/CCRateWidgetApp.swift CCRateWidget/Info.plist CCRateWidget/SettingsView.swift
git commit -m "feat(app): add opt-in menu-bar mode and notification permission"
```

---

## Task 21: README + manual QA checklist + CHANGELOG

**Files:**
- Modify: `README.md`
- Create: `docs/MANUAL_QA.md` (referenced from README)

- [ ] **Step 1: Update `README.md` Features section**

Replace the Features bullet list in `README.md` with:

```markdown
- **JSONL-primary data** — reads `~/.claude/projects/**/*.jsonl` locally; no network round-trip required
- **Per-project view** — see which projects burned which share of your current 5-hour and 7-day windows
- **Burn-rate alerts** — macOS notifications at 80% and 95% plus a "you'll hit the limit in X min" forecast
- **Three widget sizes** — Small, Medium, Large (Top-3 project strip on Large)
- **Opt-in menu bar mode** — keep the app alive in the background so alerts can fire
- **Optional OAuth** — pull Anthropic's official quota numbers when available (off by default)
```

In the Changelog section, add:

```markdown
### v1.7.0

- **Hybrid data source.** Local JSONL parsing is now the primary path; OAuth is optional and off by default.
- **Per-project attribution.** New Projects tab in the main app; Large widget shows Top 3 projects.
- **Burn-rate alerts.** 80% / 95% thresholds and ETA-to-100% forecasting via macOS notifications.
- **Opt-in menu bar mode.** Keep the app alive for background alerts.
- **App Sandbox dropped on main app** (widget extension remains sandboxed). Enables reading `~/.claude/`.
```

- [ ] **Step 2: Add `docs/MANUAL_QA.md`**

```markdown
# Manual QA — 1.7

Pre-release smoke checklist. All items must pass on a clean macOS 14.4+ build.

1. **Home folder access denied.** Deny the NSOpenPanel prompt on first launch. Confirm Dashboard shows the Setup Guide with a "Grant access" button. Click it → confirm the panel reopens and access works after granting.
2. **JSONL ingest.** Append a new assistant line to any file under `~/.claude/projects/`. Wait up to 5 minutes. Confirm the widget's 5-hour bar increases.
3. **80% alert.** In Settings, set Plan tier to Pro. Manually generate enough activity (or temporarily edit `limits.json` in App Group container) to push utilization above 80%. Confirm one macOS notification fires. Confirm a second tick at 82% does **not** fire again.
4. **Menu-bar mode toggle.** Toggle "Run in menu bar". Click "Quit and reopen". Confirm a "CC" status-bar item appears with Refresh / Open / Quit.
5. **OAuth toggle.** Enable OAuth in Settings. Log in. Confirm the widget badge changes from "LOCAL" to "OAUTH" or "HYBRID" once a tick completes. Disable. Confirm no further OAuth calls (verify via Console.app NSLog filter).
6. **Per-project view.** Confirm the Projects tab lists projects with token totals and $ cost. Confirm Top 3 appear on the Large widget.
7. **Backfill.** On first launch after upgrade, observe `RateDataSource = .partial` briefly; confirm it flips to `.jsonl` once backfill completes (look for "Learning…" badge → "LOCAL").
```

- [ ] **Step 3: Commit**

```bash
git add README.md docs/MANUAL_QA.md
git commit -m "docs: 1.7 features, changelog, manual QA checklist"
```

---

## Task 22: CI — run unit tests on push

**Files:**
- Modify: `.github/workflows/<existing build workflow>.yml`

- [ ] **Step 1: Inspect existing workflow**

Run: `ls .github/workflows/`
Open the build workflow (likely `build.yml` or `release.yml`). Locate the `xcodebuild build` step.

- [ ] **Step 2: Add a test step**

Insert immediately after `xcodegen generate` (and before the build / release steps):

```yaml
      - name: Run unit tests
        run: |
          xcodebuild test \
            -project CCRateWidget.xcodeproj \
            -scheme CCRateWidget \
            -destination 'platform=macOS' \
            -quiet
```

Ensure the runner is `macos-14` or newer. If the existing workflow uses `macos-13`, bump it.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/
git commit -m "ci: run unit tests on push"
```

---

## Task 23: Version bump and release prep

**Files:**
- Modify: `project.yml` (if it carries `CFBundleShortVersionString` / `CFBundleVersion`)
- Modify: `CCRateWidget/Info.plist`
- Modify: `RateWidgetExtension/Info.plist`

- [ ] **Step 1: Find the version source**

Run: `grep -rn "1.5.2\|CFBundleShortVersion" CCRateWidget/Info.plist RateWidgetExtension/Info.plist project.yml`
Identify where version strings live.

- [ ] **Step 2: Bump versions to 1.7.0**

Set `CFBundleShortVersionString` to `1.7.0` and `CFBundleVersion` to the next monotonically increasing integer (e.g. if current build is 12, use 13) in both Info.plist files.

- [ ] **Step 3: Build and test once more**

Run: `xcodegen generate && xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -quiet`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add CCRateWidget/Info.plist RateWidgetExtension/Info.plist project.yml
git commit -m "chore: bump version to 1.7.0"
```

---

## Final verification

After Task 23, run the full suite one more time:

- `xcodegen generate`
- `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS'`
- Manual QA checklist in `docs/MANUAL_QA.md`

Open a PR titled `feat: 1.7 hybrid data source (local JSONL + per-project + alerts)` and request review.

---

## Spec coverage map

- ToS-hedge motivation, sandbox drop → Task 2.
- New types (`RateDataSource`, `ProjectBreakdown`, `InferredLimits`) → Task 3.
- Pricing table → Task 4.
- App Group store (rate / projects / limits / offsets / alert_state) → Tasks 5, 13.
- JSONL decoding + incremental tail + window aggregation → Tasks 6, 7, 8.
- P90 inference + override precedence → Task 9.
- Threshold + burn-rate forecast alerts → Tasks 10, 13.
- OAuth demotion → Task 11.
- Coordinator timer + tick → Tasks 12, 13, 19.
- Widget Top-3 + source badge → Tasks 14, 15.
- Main-app Settings + project list + setup guide → Tasks 16, 17, 18.
- Backfill 6 weeks → Task 19.
- Menu-bar mode + notification permission → Task 20.
- README / CHANGELOG / manual QA → Task 21.
- CI tests → Task 22.
- Version bump → Task 23.
