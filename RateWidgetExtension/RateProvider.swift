import WidgetKit

struct RateEntry: TimelineEntry {
    let date: Date
    let data: RateData
    let projects: ProjectBreakdown?

    static let placeholder = RateEntry(date: Date(), data: .placeholder, projects: nil)
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
