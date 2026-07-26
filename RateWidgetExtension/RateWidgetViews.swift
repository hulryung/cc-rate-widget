import SwiftUI
import WidgetKit

// MARK: - Entry View (routes to size-specific views)

struct RateWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: RateEntry

    var body: some View {
        if entry.data.status == .noLocalData {
            SetupPromptView(family: family)
        } else {
            switch family {
            case .systemSmall:  SmallWidgetView(entry: entry)
            case .systemMedium: MediumWidgetView(entry: entry)
            case .systemLarge:  LargeWidgetView(entry: entry)
            default:            MediumWidgetView(entry: entry)
            }
        }
    }
}

// MARK: - Setup Prompt

struct SetupPromptView: View {
    let family: WidgetFamily

    var body: some View {
        VStack(spacing: family == .systemSmall ? Metric.widgetTight : Metric.widgetGroup) {
            Image(systemName: "folder.badge.questionmark")
                .font(family == .systemSmall ? .title3 : .largeTitle)
                .foregroundStyle(.secondary)
            Text("Setup required")
                .font(family == .systemSmall ? WidgetType.label : WidgetType.value)
            Text("Open the app to grant access")
                .font(WidgetType.micro)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .widgetURL(URL(string: "clauderatewidget://setup"))
    }
}

// MARK: - Small

/// Two numbers, nothing else. At 150pt the app's own name is the least useful thing
/// that could occupy a line.
struct SmallWidgetView: View {
    let entry: RateEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.widgetGroup) {
            metric(label: "5h", data: entry.data.session)
            Divider()
            metric(label: "7d", data: entry.data.weekly)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topTrailing) {
            StatusDot(status: entry.data.status)
        }
    }

    private func metric(label: String, data: CategoryData) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: Metric.widgetTight) {
                Text(label).font(WidgetType.micro).foregroundStyle(.secondary)
                if let u = data.utilization {
                    Text("\(Int(u * 100))%")
                        .font(WidgetType.micro).bold()
                        .foregroundStyle(UsageLevel(u).tint)
                }
            }
            Text(UsageFormat.tokens(data.tokens))
                .font(WidgetType.hero)
                .minimumScaleFactor(0.7).lineLimit(1)
            if data.cost > 0 {
                Text(UsageFormat.cost(data.cost))
                    .font(WidgetType.micro).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

// MARK: - Medium

struct MediumWidgetView: View {
    let entry: RateEntry

    var body: some View {
        HStack(spacing: Metric.widgetGroup) {
            column(label: "Session 5h", data: entry.data.session)
            Divider()
            column(label: "Weekly 7d", data: entry.data.weekly)
            Divider()
            column(label: "Sonnet 7d", data: entry.data.weeklySonnet)
        }
        .overlay(alignment: .topTrailing) {
            StatusDot(status: entry.data.status)
        }
    }

    private func column(label: String, data: CategoryData) -> some View {
        VStack(alignment: .leading, spacing: Metric.widgetTight) {
            Text(label)
                .font(WidgetType.micro).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)

            Text(UsageFormat.tokens(data.tokens))
                .font(WidgetType.hero)
                .minimumScaleFactor(0.6).lineLimit(1)

            if let u = data.utilization {
                UsageBar(utilization: u, height: Metric.widgetBar)
                Text("\(Int(u * 100))%")
                    .font(WidgetType.micro).monospacedDigit()
                    .foregroundStyle(UsageLevel(u).tint)
            } else if data.cost > 0 {
                Text(UsageFormat.cost(data.cost))
                    .font(WidgetType.micro).foregroundStyle(.secondary).monospacedDigit()
            }

            Spacer(minLength: 0)

            if let reset = data.resetsAt {
                Text(UsageFormat.remainingCoarse(until: reset) + " left")
                    .font(WidgetType.micro).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Large

struct LargeWidgetView: View {
    let entry: RateEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.widgetGroup) {
            row(label: "Session", window: "5h", data: entry.data.session)
            row(label: "Weekly", window: "7d", data: entry.data.weekly)
            row(label: "Sonnet", window: "7d", data: entry.data.weeklySonnet)

            Divider()
            ProjectStrip(projects: entry.projects ?? ProjectBreakdown(entries: []))

            Spacer(minLength: 0)

            HStack(spacing: Metric.widgetTight) {
                Text(entry.data.source.shortLabel)
                Spacer()
                Text(entry.date.formatted(date: .omitted, time: .shortened))
            }
            .font(WidgetType.micro).foregroundStyle(.tertiary)
        }
        .overlay(alignment: .topTrailing) {
            StatusDot(status: entry.data.status)
        }
    }

    private func row(label: String, window: String, data: CategoryData) -> some View {
        VStack(alignment: .leading, spacing: Metric.widgetTight) {
            HStack(alignment: .firstTextBaseline, spacing: Metric.widgetTight) {
                Text(label).font(WidgetType.label).foregroundStyle(.secondary)
                Text(window).font(WidgetType.micro).foregroundStyle(.tertiary)
                Spacer()
                Text(UsageFormat.tokens(data.tokens) + " tok")
                    .font(WidgetType.value)
                if data.cost > 0 {
                    Text(UsageFormat.cost(data.cost))
                        .font(WidgetType.micro).foregroundStyle(.secondary).monospacedDigit()
                }
                if let u = data.utilization {
                    Text("\(Int(u * 100))%")
                        .font(WidgetType.value)
                        .foregroundStyle(UsageLevel(u).tint)
                        .frame(minWidth: 38, alignment: .trailing)   // reserve width so rows align
                }
            }
            if let u = data.utilization {
                UsageBar(utilization: u, height: Metric.widgetBar)
            }
            if let reset = data.resetsAt {
                Text("Resets \(UsageFormat.resetMoment(reset)) · \(UsageFormat.remainingCoarse(until: reset)) left")
                    .font(WidgetType.micro).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }
}

// MARK: - Shared parts

/// Renders nothing when healthy — a dot that is always present is a dot nobody reads.
private struct StatusDot: View {
    let status: OverallStatus
    var body: some View {
        if let ind = status.indicator {
            Image(systemName: ind.symbol)
                .font(.system(size: 10))
                .foregroundStyle(ind.color)
                .accessibilityLabel("Status: \(ind.label)")
        }
    }
}

struct ProjectStrip: View {
    let projects: ProjectBreakdown
    var body: some View {
        let top = projects.topN(3)
        VStack(alignment: .leading, spacing: Metric.widgetTight) {
            Text("Top projects").font(WidgetType.micro).foregroundStyle(.secondary)
            if top.isEmpty {
                Text("No activity yet").font(WidgetType.micro).foregroundStyle(.tertiary)
            } else {
                ForEach(top) { entry in
                    HStack(spacing: Metric.widgetTight) {
                        Text(entry.displayName)
                            .font(WidgetType.micro).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("\(UsageFormat.tokens(entry.tokens)) · \(UsageFormat.cost(entry.cost))")
                            .font(WidgetType.micro).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    RateWidget()
} timeline: {
    RateEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    RateWidget()
} timeline: {
    RateEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    RateWidget()
} timeline: {
    RateEntry.placeholder
}
