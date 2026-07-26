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
        case .dashboard: DashboardPane(rate: coordinator.lastSnapshot, projects: projects)
        case .projects:  ProjectsPane(projects: projects)
        }
    }

    private func refreshProjects() {
        projects = try? LocalStore.shared.readProjects()
    }
}

// MARK: - Dashboard

private struct DashboardPane: View {
    let rate: RateData?
    let projects: ProjectBreakdown?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.section) {
                if rate?.status == .noLocalData {
                    SetupPane()
                } else if let rate {
                    UsageSummary(rate: rate)
                    // The three cards leave most of the window empty on their own, and
                    // "which project burned this" is the natural next question.
                    if let projects, !projects.entries.isEmpty {
                        TopProjectsCard(projects: projects)
                    }
                } else {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(Metric.screen)
        }
    }
}

private struct TopProjectsCard: View {
    let projects: ProjectBreakdown

    var body: some View {
        let top = projects.topN(5)
        let maxTokens = max(top.first?.tokens ?? 1, 1)

        VStack(alignment: .leading, spacing: Metric.tight) {
            Text("Top projects").font(AppType.label).foregroundStyle(.secondary)

            ForEach(top) { entry in
                HStack(spacing: Metric.group) {
                    Text(entry.displayName)
                        .font(AppType.value)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(width: 150, alignment: .leading)

                    // Relative bar: the comparison between projects is the point, so
                    // scale against the largest rather than against a usage limit.
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.accentColor.opacity(0.35))
                            .frame(width: geo.size.width * CGFloat(entry.tokens) / CGFloat(maxTokens))
                    }
                    .frame(height: 6)

                    Text("\(UsageFormat.tokens(entry.tokens)) tok")
                        .font(AppType.detail).monospacedDigit()
                        .frame(width: 80, alignment: .trailing)
                    Text(UsageFormat.cost(entry.cost))
                        .font(AppType.detail).foregroundStyle(.secondary).monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                }
            }
        }
        .usageCard()
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
