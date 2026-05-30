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
        VStack(spacing: family == .systemSmall ? 6 : 10) {
            Image(systemName: "folder.badge.questionmark")
                .font(family == .systemSmall ? .title3 : .largeTitle)
                .foregroundStyle(.orange)
            Text("Setup Required")
                .font(family == .systemSmall ? .caption.bold() : .headline)
            Text("Open the app to grant access to ~/.claude")
                .font(family == .systemSmall ? .system(size: 9) : .caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .widgetURL(URL(string: "clauderatewidget://setup"))
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let entry: RateEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(statusColor(entry.data.status)).frame(width: 7, height: 7)
                Text("Claude").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            usageLine(label: "5h", data: entry.data.session)
            Spacer(minLength: 6)
            usageLine(label: "7d", data: entry.data.weekly)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topTrailing) {
            SourceBadge(source: entry.data.source).padding(6)
        }
    }

    private func usageLine(label: String, data: CategoryData) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text("\(UsageFormat.tokens(data.tokens)) tok")
                .font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
            if data.cost > 0 {
                Text(UsageFormat.cost(data.cost))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let entry: RateEntry

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(statusColor(entry.data.status)).frame(width: 8, height: 8)
                Text("Claude Rate Monitor").font(.caption2.bold()).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 12) {
                categoryColumn(label: "Session 5h", data: entry.data.session)
                categoryColumn(label: "Weekly 7d", data: entry.data.weekly)
                categoryColumn(label: "Sonnet 7d", data: entry.data.weeklySonnet)
            }
        }
        .padding(2)
        .overlay(alignment: .topTrailing) {
            SourceBadge(source: entry.data.source).padding(6)
        }
    }

    private func categoryColumn(label: String, data: CategoryData) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Text(UsageFormat.tokens(data.tokens))
                .font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
            if data.cost > 0 {
                Text(UsageFormat.cost(data.cost))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            if let reset = data.resetsAt {
                Text(resetText(reset)).font(.system(size: 8)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Large Widget

struct LargeWidgetView: View {
    let entry: RateEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(statusColor(entry.data.status)).frame(width: 10, height: 10)
                Text("Claude Rate Monitor").font(.system(size: 15, weight: .bold)).foregroundStyle(.secondary)
                Spacer()
            }

            detailRow(label: "Session (5h)", data: entry.data.session)
            detailRow(label: "Weekly (7d)", data: entry.data.weekly)
            detailRow(label: "Weekly Sonnet", data: entry.data.weeklySonnet)

            Divider()
            LargeProjectStrip(projects: entry.projects ?? ProjectBreakdown(entries: []))

            Spacer(minLength: 0)

            Text("Updated \(entry.date.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .overlay(alignment: .topTrailing) {
            SourceBadge(source: entry.data.source).padding(6)
        }
    }

    private func detailRow(label: String, data: CategoryData) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(UsageFormat.tokens(data.tokens)) tok")
                        .font(.system(size: 19, weight: .bold, design: .rounded)).monospacedDigit()
                    if data.cost > 0 {
                        Text(UsageFormat.cost(data.cost))
                            .font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                if let reset = data.resetsAt {
                    Text("Resets \(resetText(reset))").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Source Badge

struct SourceBadge: View {
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
        case .jsonl:       return .secondary
        case .oauth:       return .blue
        case .hybrid:      return .green
        case .partial:     return .orange
        case .noLocalData: return .red
        }
    }
}

// MARK: - Large Project Strip

struct LargeProjectStrip: View {
    let projects: ProjectBreakdown
    var body: some View {
        let top = projects.topN(3)
        VStack(alignment: .leading, spacing: 4) {
            Text("Top projects").font(.caption2).foregroundStyle(.secondary)
            ForEach(top) { entry in
                HStack {
                    Text(entry.displayName).font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text("\(UsageFormat.tokens(entry.tokens)) · \(UsageFormat.cost(entry.cost))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if top.isEmpty {
                Text("No activity yet").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shared Helpers

private func statusColor(_ status: OverallStatus) -> Color {
    switch status {
    case .active: return .green
    case .warning: return .orange
    case .rateLimited, .unauthorized, .forbidden: return .red
    case .notLoggedIn: return .orange
    case .error, .unknown, .noLocalData: return .gray
    }
}

private func resetText(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
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
