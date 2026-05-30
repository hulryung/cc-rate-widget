import Foundation

enum Backfill {
    static let weeksBack = 6
    private static let didRunKey = "backfill_didRun_v1"

    static var didRun: Bool {
        UserDefaults.standard.bool(forKey: didRunKey)
    }

    static func runIfNeeded(rootDir: URL, store: AppGroupStore) {
        guard !didRun else { return }
        // Set the guard flag BEFORE the scan so concurrent runOnce() calls
        // don't each launch their own scan. Reset on failure so the user
        // gets retried later instead of being stuck in a no-history state.
        UserDefaults.standard.set(true, forKey: didRunKey)
        Task.detached(priority: .background) {
            do {
                let samples = try buildWeeklySamples(rootDir: rootDir)
                // Merge under the limits lock so a concurrent tick can't drop these samples.
                try store.mutateLimits { $0.weeklySamples = samples }
                await MainActor.run { AggregationCoordinator.shared.runOnce() }
            } catch {
                NSLog("[Backfill] failed: \(error)")
                UserDefaults.standard.set(false, forKey: didRunKey)
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
