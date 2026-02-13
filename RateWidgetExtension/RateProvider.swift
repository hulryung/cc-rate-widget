import WidgetKit

struct RateEntry: TimelineEntry {
    let date: Date
    let data: RateData
    let isPlaceholder: Bool

    static let placeholder = RateEntry(
        date: Date(),
        data: .placeholder,
        isPlaceholder: true
    )
}

struct RateProvider: TimelineProvider {
    func placeholder(in context: Context) -> RateEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (RateEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        // Try cached data first, then fetch
        if let cached = CredentialManager.shared.loadCachedRateData() {
            completion(RateEntry(date: Date(), data: cached, isPlaceholder: false))
        } else {
            Task {
                let data = await RateFetcher.shared.fetchRateData()
                completion(RateEntry(date: Date(), data: data, isPlaceholder: false))
            }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RateEntry>) -> Void) {
        Task {
            let data: RateData
            // Try fetching live data first
            let fetched = await RateFetcher.shared.fetchRateData()
            if fetched.status == .error || fetched.status == .unauthorized || fetched.status == .notLoggedIn {
                // Fall back to cached data if available
                data = CredentialManager.shared.loadCachedRateData() ?? fetched
            } else {
                data = fetched
                CredentialManager.shared.saveCachedRateData(data)
            }
            let entry = RateEntry(date: Date(), data: data, isPlaceholder: false)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
}
