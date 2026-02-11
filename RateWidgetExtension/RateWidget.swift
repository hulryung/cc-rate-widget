import WidgetKit
import SwiftUI

@main
struct RateWidgetBundle: WidgetBundle {
    var body: some Widget {
        RateWidget()
    }
}

struct RateWidget: Widget {
    let kind: String = "com.dkkang.cc-rate-widget.rate"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RateProvider()) { entry in
            RateWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Rate Monitor")
        .description("Monitor your Claude Code rate limits")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
