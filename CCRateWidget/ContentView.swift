import SwiftUI

struct ContentView: View {
    @StateObject private var coordinator = AggregationCoordinator.shared
    @State private var projects: ProjectBreakdown?
    @State private var tab: Tab = .dashboard

    enum Tab: String, CaseIterable { case dashboard = "Dashboard", projects = "Projects", settings = "Settings" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).padding()

            Divider()
            Group {
                switch tab {
                case .dashboard: DashboardSection(rate: coordinator.lastSnapshot)
                case .projects:  ProjectsSection(projects: projects)
                case .settings:  SettingsView()
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 520, minHeight: 420)
        .task {
            // AppDelegate owns coordinator lifecycle (start on launch). Here we only
            // surface the latest snapshot/projects when the window appears.
            refreshProjects()
        }
        .onReceive(coordinator.$lastSnapshot) { _ in refreshProjects() }
    }

    private func refreshProjects() {
        projects = try? AppGroupStore.shared.readProjects()
    }
}

private struct DashboardSection: View {
    let rate: RateData?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if rate?.status == .noLocalData {
                SetupGuide()
            } else if let rate {
                LimitRow(label: "5-hour session", cat: rate.session)
                LimitRow(label: "7-day",           cat: rate.weekly)
                LimitRow(label: "7-day Sonnet",    cat: rate.weeklySonnet)
                Text("Source: \(rate.source.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView("Loading…")
            }
        }
        .padding()
    }
}

private struct LimitRow: View {
    let label: String
    let cat: CategoryData
    var showCost: Bool = true
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(UsageFormat.tokens(cat.tokens)) tok")
                    .font(.title3.weight(.semibold)).monospacedDigit()
                if showCost && cat.cost > 0 {
                    Text(UsageFormat.cost(cat.cost))
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                if let resetsAt = cat.resetsAt {
                    Text("resets \(resetsAt, style: .relative)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ProjectsSection: View {
    let projects: ProjectBreakdown?
    var body: some View {
        Group {
            if let projects, !projects.entries.isEmpty {
                List(projects.topN(20)) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.displayName).font(.body)
                            Text(entry.path).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(entry.tokens / 1000)k tok").monospacedDigit()
                            Text(String(format: "$%.2f", entry.cost))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("No project activity in current windows.")
                    .foregroundStyle(.secondary).padding()
            }
        }
    }
}

private struct SetupGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setup required").font(.title2.bold())
            Text("Claude Rate Widget reads ~/.claude/projects/ on this Mac to compute your usage. We'll request permission once.")
            Button("Grant access") { HomeAccessPrompter.shared.prompt() }
        }.padding()
    }
}
