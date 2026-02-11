import SwiftUI
import WidgetKit

// MARK: - Entry View (routes to size-specific views)

struct RateWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: RateEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            MediumWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let entry: RateEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor(entry.data.status))
                    .frame(width: 7, height: 7)
                Text("Claude")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            miniBar(label: "Session", value: entry.data.session.utilization)
            Spacer(minLength: 3)
            miniBar(label: "Weekly", value: entry.data.weekly.utilization)

            Spacer(minLength: 4)

            Text(entry.data.status.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(statusColor(entry.data.status))
        }
    }

    private func miniBar(label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 3)
                    Capsule()
                        .fill(barColor(value))
                        .frame(width: geo.size.width * min(value, 1.0), height: 3)
                }
            }
            .frame(height: 3)
        }
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let entry: RateEntry

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor(entry.data.status))
                    .frame(width: 8, height: 8)
                Text("Claude Rate Monitor")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.data.status.label)
                    .font(.caption2.bold())
                    .foregroundStyle(statusColor(entry.data.status))
            }

            HStack(spacing: 12) {
                categoryColumn(label: "Session", data: entry.data.session)
                categoryColumn(label: "Weekly", data: entry.data.weekly)
                categoryColumn(label: "Sonnet", data: entry.data.weeklySonnet)
                if entry.data.overage.isEnabled {
                    overageColumn(entry.data.overage)
                }
            }
        }
        .padding(2)
    }

    private func categoryColumn(label: String, data: CategoryData) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("\(Int(data.utilization * 100))%")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(barColor(data.utilization))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 4)
                    Capsule().fill(barColor(data.utilization))
                        .frame(width: geo.size.width * min(data.utilization, 1.0), height: 4)
                }
            }
            .frame(height: 4)
            if let reset = data.resetsAt {
                Text(resetText(reset))
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func overageColumn(_ data: OverageData) -> some View {
        VStack(spacing: 4) {
            Text("Overage")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("$\(String(format: "%.0f", data.spent))")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(barColor(data.utilization))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 4)
                    Capsule().fill(barColor(data.utilization))
                        .frame(width: geo.size.width * min(data.utilization, 1.0), height: 4)
                }
            }
            .frame(height: 4)
            Text("of $\(String(format: "%.0f", data.limit))")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Large Widget

struct LargeWidgetView: View {
    let entry: RateEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor(entry.data.status))
                    .frame(width: 10, height: 10)
                Text("Claude Rate Monitor")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.data.status.label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(statusColor(entry.data.status))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(statusColor(entry.data.status).opacity(0.15), in: Capsule())
            }

            detailRow(label: "Session (5h)", data: entry.data.session)
            detailRow(label: "Weekly", data: entry.data.weekly)
            detailRow(label: "Weekly Sonnet", data: entry.data.weeklySonnet)

            if entry.data.overage.isEnabled {
                overageDetailRow(entry.data.overage)
            }

            Spacer(minLength: 0)

            Text("Updated \(entry.date.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func detailRow(label: String, data: CategoryData) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(data.utilization * 100))%")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(barColor(data.utilization))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 8)
                    Capsule().fill(barColor(data.utilization))
                        .frame(width: geo.size.width * min(data.utilization, 1.0), height: 8)
                }
            }
            .frame(height: 8)
            if let reset = data.resetsAt {
                Text("Resets \(resetText(reset))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func overageDetailRow(_ data: OverageData) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Overage")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("$\(String(format: "%.2f", data.spent)) / $\(String(format: "%.2f", data.limit))")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(barColor(data.utilization))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 8)
                    Capsule().fill(barColor(data.utilization))
                        .frame(width: geo.size.width * min(data.utilization, 1.0), height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Shared Helpers

private func statusColor(_ status: OverallStatus) -> Color {
    switch status {
    case .active: return .green
    case .warning: return .orange
    case .rateLimited: return .red
    case .error, .unknown: return .gray
    }
}

private func barColor(_ utilization: Double) -> Color {
    if utilization >= 1.0 { return .red }
    if utilization >= 0.8 { return .orange }
    return .green
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
