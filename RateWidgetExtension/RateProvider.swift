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
        Task {
            let data = await RateFetcher.shared.fetchRateData()
            completion(RateEntry(date: Date(), data: data, isPlaceholder: false))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RateEntry>) -> Void) {
        Task {
            let data = await RateFetcher.shared.fetchRateData()
            let entry = RateEntry(date: Date(), data: data, isPlaceholder: false)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
}
