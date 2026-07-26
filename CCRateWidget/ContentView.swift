import SwiftUI

struct ContentView: View {
    @StateObject private var coordinator = AggregationCoordinator.shared
    @State private var projects: ProjectBreakdown?
    @State private var pane: Pane = .dashboard

    /// Not named `Section` — that shadows SwiftUI's `Section`, which this file also uses.
    enum Pane: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard", projects = "Projects"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.67percent"
            case .projects:  return "folder"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 160, max: 190)
            .listStyle(.sidebar)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationTitle(pane.rawValue)
        }
        .frame(minWidth: 720, minHeight: 480)
        .task { refreshProjects() }
        .onReceive(coordinator.$lastSnapshot) { _ in refreshProjects() }
    }

    @ViewBuilder private var detail: some View {
        switch pane {
        case .dashboard: DashboardPane(rate: coordinator.lastSnapshot)
        case .projects:  ProjectsPane(projects: projects)
        }
    }

    private func refreshProjects() {
        projects = try? AppGroupStore.shared.readProjects()
    }
}

// MARK: - Dashboard

private struct DashboardPane: View {
    let rate: RateData?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.section) {
                if rate?.status == .noLocalData {
                    SetupPane()
                } else if let rate {
                    HeroCard(cat: rate.weekly, burnPerSec: rate.burnTokensPerSecond, plan: rate.planName)
                    HStack(alignment: .top, spacing: Metric.section) {
                        StatCard(label: "Session", window: "5 hours",
                                 cat: rate.session, plan: rate.planName)
                        StatCard(label: "Sonnet", window: "7 days",
                                 cat: rate.weeklySonnet, plan: rate.planName)
                    }
                    .fixedSize(horizontal: false, vertical: true)   // equal heights
                    FooterLine(rate: rate)
                } else {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(Metric.screen)
        }
    }
}

/// Weekly usage — the number the user actually plans around, so it gets the hero slot.
private struct HeroCard: View {
    let cat: CategoryData
    var burnPerSec: Double = 0
    var plan: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.group) {
            HStack(spacing: Metric.gutter) {
                Text("Weekly").font(AppType.title)
                Text("7 days").font(AppType.detail).foregroundStyle(.tertiary)
                Spacer()
                if let plan { PlanPill(plan) }
                if let u = cat.utilization { UsageChip(utilization: u) }
            }

            HStack(alignment: .firstTextBaseline, spacing: Metric.tight) {
                Text(UsageFormat.tokens(cat.tokens))
                    .font(AppType.hero)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: cat.tokens)
                Text("tok").font(AppType.detail).foregroundStyle(.secondary)
                Spacer()
                if cat.cost > 0 {
                    Text(UsageFormat.cost(cat.cost))
                        .font(AppType.metric).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.2), value: cat.cost)
                }
            }

            if let u = cat.utilization {
                UsageBar(utilization: u, animated: true)
            }

            HStack(spacing: Metric.gutter) {
                if let caption = limitCaption(cat, plan: plan) {
                    Text(caption).font(AppType.detail).foregroundStyle(.secondary)
                }
                Spacer()
                if let resetsAt = cat.resetsAt {
                    ResetLine(date: resetsAt)
                }
            }
        }
        .usageCard()
    }
}

private struct StatCard: View {
    let label: String
    let window: String
    let cat: CategoryData
    var plan: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.tight) {
            HStack(spacing: Metric.gutter) {
                Text(label).font(AppType.label).foregroundStyle(.secondary)
                Text(window).font(AppType.micro).foregroundStyle(.tertiary)
                Spacer()
                if let u = cat.utilization { UsageChip(utilization: u) }
            }

            HStack(alignment: .firstTextBaseline, spacing: Metric.gutter) {
                Text(UsageFormat.tokens(cat.tokens))
                    .font(AppType.metric)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: cat.tokens)
                Text("tok").font(AppType.detail).foregroundStyle(.secondary)
                Spacer()
                if cat.cost > 0 {
                    Text(UsageFormat.cost(cat.cost))
                        .font(AppType.detail).foregroundStyle(.secondary).monospacedDigit()
                }
            }

            if let u = cat.utilization {
                UsageBar(utilization: u, animated: true)
            }

            Spacer(minLength: 0)

            if let resetsAt = cat.resetsAt {
                ResetLine(date: resetsAt)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .usageCard()
    }
}

// MARK: - Small parts

private struct PlanPill: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(AppType.micro)
            .padding(.horizontal, Metric.tight).padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            .foregroundStyle(Color.accentColor)
    }
}

/// Reset moment plus a coarse "time left" — deliberately no minutes, since the underlying
/// reset instant is only accurate to the hour.
private struct ResetLine: View {
    let date: Date
    var body: some View {
        HStack(spacing: Metric.gutter) {
            Text(UsageFormat.resetMoment(date))
            Text(UsageFormat.remainingCoarse(until: date) + " left")
                .padding(.horizontal, Metric.gutter).padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
        .font(AppType.micro)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Resets \(UsageFormat.resetMoment(date))")
    }
}

/// Where the numbers came from, and when — one quiet line rather than a badge per card.
private struct FooterLine: View {
    let rate: RateData

    var body: some View {
        HStack(spacing: Metric.gutter) {
            if let ind = rate.status.indicator {
                Image(systemName: ind.symbol).foregroundStyle(ind.color)
                Text(ind.label).accessibilityLabel("Status: \(ind.label)")
                Text("·").foregroundStyle(.tertiary)
            }
            Text(rate.source.shortLabel)
            Spacer()
            Text("Updated \(rate.fetchedAt, style: .time)")
        }
        .font(AppType.micro)
        .foregroundStyle(.secondary)
    }
}

/// Worded by what the denominator actually means, so a percentage is never presented as
/// Anthropic's quota when it is really the user's own observed peak.
private func limitCaption(_ cat: CategoryData, plan: String?) -> String? {
    guard let kind = cat.limitKind, let u = cat.utilization else { return nil }
    switch kind {
    case .official:
        return plan.map { "Anthropic quota · \($0)" } ?? "Anthropic quota"
    case .userLimit:
        guard let limit = cat.limitTokens else { return nil }
        return "of \(UsageFormat.tokens(limit)) tok limit"
    case .typicalPeak:
        guard let limit = cat.limitTokens else { return nil }
        _ = u
        return "of your typical peak (\(UsageFormat.tokens(limit)) tok)"
    }
}

// MARK: - Projects

private struct ProjectsPane: View {
    let projects: ProjectBreakdown?

    var body: some View {
        if let projects, !projects.entries.isEmpty {
            List {
                Section("Last 7 days") {
                    ForEach(projects.topN(30)) { entry in
                        HStack(spacing: Metric.group) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.displayName).font(AppType.value)
                                Text(entry.path)
                                    .font(AppType.detail).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(UsageFormat.tokens(entry.tokens)) tok")
                                    .font(AppType.value)
                                Text(UsageFormat.cost(entry.cost))
                                    .font(AppType.detail).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } else {
            ContentUnavailableView("No activity yet",
                                   systemImage: "folder",
                                   description: Text("Projects appear here once you've used Claude Code in the last 7 days."))
        }
    }
}

// MARK: - Setup

private struct SetupPane: View {
    var body: some View {
        ContentUnavailableView {
            Label("Setup required", systemImage: "folder.badge.questionmark")
        } description: {
            Text("Claude Rate Widget reads ~/.claude/projects/ on this Mac to compute your usage. macOS will ask for permission once.")
        } actions: {
            Button("Grant Access") { HomeAccessPrompter.shared.prompt() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}
