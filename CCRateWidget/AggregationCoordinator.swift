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
        let store = AppGroupStore.shared
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

        func cat(tokens: Int, cost: Double, earliest: Date?, window: TimeInterval) -> CategoryData {
            CategoryData(tokens: tokens, cost: cost,
                         resetsAt: earliest.map { $0.addingTimeInterval(window) })
        }

        let rate = RateData(
            session:      cat(tokens: snap.fiveHourTokens, cost: snap.fiveHourCost,
                              earliest: snap.earliestInFiveHour, window: 5 * 3600),
            weekly:       cat(tokens: snap.sevenDayTokens, cost: snap.sevenDayCost,
                              earliest: snap.earliestInSevenDay, window: 7 * 86400),
            // Sonnet cost isn't tracked per-window yet; tokens are accurate.
            weeklySonnet: cat(tokens: snap.sevenDaySonnetTokens, cost: 0,
                              earliest: snap.earliestInSevenDay, window: 7 * 86400),
            fetchedAt: now,
            status: .active,
            source: .jsonl
        )

        try store.writeRate(rate)
        return rate
    }
}
