import SwiftUI

struct ContentView: View {
    @StateObject private var coordinator = AggregationCoordinator.shared
    @State private var projects: ProjectBreakdown?
    @State private var section: Section = .dashboard

    enum Section: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard", projects = "Projects", settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.67percent"
            case .projects:  return "folder"
            case .settings:  return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
            .listStyle(.sidebar)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationTitle(section.rawValue)
        }
        .frame(minWidth: 680, minHeight: 460)
        .task {
            refreshProjects()
        }
        .onReceive(coordinator.$lastSnapshot) { _ in refreshProjects() }
    }

    @ViewBuilder private var detail: some View {
        switch section {
        case .dashboard: DashboardSection(rate: coordinator.lastSnapshot)
        case .projects:  ProjectsSection(projects: projects)
        case .settings:  SettingsView()
        }
    }

    private func refreshProjects() {
        projects = try? AppGroupStore.shared.readProjects()
    }
}

// MARK: - Card chrome

private extension View {
    func card() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

private func pctColor(_ u: Double) -> Color {
    if u >= 1.0 { return .red }
    if u >= 0.8 { return .orange }
    return .green
}

/// Rounded, color-coded usage bar with the percentage labelled inside/over it.
private struct UsageBar: View {
    let utilization: Double      // 0…1+
    var height: CGFloat = 12
    var showLabel: Bool = true

    var body: some View {
        let u = max(0, utilization)
        let clamped = min(u, 1.0)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(pctColor(u).gradient)
                    .frame(width: max(height, geo.size.width * clamped))
            }
            .overlay(alignment: .trailing) {
                if showLabel {
                    Text("\(Int(u * 100))%")
                        .font(.system(size: height * 0.8, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 2)
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Dashboard

private struct DashboardSection: View {
    let rate: RateData?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if rate?.status == .noLocalData {
                    SetupGuide()
                } else if let rate {
                    DashboardHeader(rate: rate)
                    HeroCard(label: "Weekly", systemImage: "calendar", cat: rate.weekly,
                             burnPerSec: rate.burnTokensPerSecond, plan: rate.planName)
                    HStack(spacing: 16) {
                        StatCard(label: "Session", sublabel: "5 hours", systemImage: "clock",
                                 cat: rate.session, burnPerSec: rate.burnTokensPerSecond, plan: rate.planName)
                        StatCard(label: "Sonnet", sublabel: "7 days", systemImage: "cpu", cat: rate.weeklySonnet)
                    }
                } else {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(20)
        }
    }
}

private struct DashboardHeader: View {
    let rate: RateData
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(.green).frame(width: 8, height: 8)
            Text("Tracking local usage")
                .font(.subheadline).foregroundStyle(.secondary)
            if let plan = rate.planName {
                Text(plan)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
            Text("Updated \(rate.fetchedAt, style: .time)")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }
}

/// Caption under a usage bar, worded by what the denominator means.
private func limitCaption(_ cat: CategoryData, plan: String? = nil) -> String? {
    guard let limit = cat.limitTokens, let kind = cat.limitKind, let u = cat.utilization else { return nil }
    switch kind {
    case .userLimit:
        return "\(UsageFormat.tokens(cat.tokens)) of \(UsageFormat.tokens(limit)) limit"
    case .typicalPeak:
        let scope = plan.map { "your \($0) typical peak" } ?? "your typical peak"
        return "\(Int(u * 100))% of \(scope) (\(UsageFormat.tokens(limit)))"
    }
}

/// "~47m to limit at current pace" when actively burning toward a denominator.
private func etaText(_ cat: CategoryData, burnPerSec: Double) -> String? {
    guard burnPerSec > 0, let limit = cat.limitTokens else { return nil }
    let remaining = Double(limit - cat.tokens)
    guard remaining > 0 else { return "over your typical peak" }
    let minutes = Int(remaining / burnPerSec / 60)
    guard minutes > 0, minutes < 100_000 else { return nil }
    return "~\(UsageFormat.duration(minutes: minutes)) to limit at current pace"
}

private struct HeroCard: View {
    let label: String
    let systemImage: String
    let cat: CategoryData
    var burnPerSec: Double = 0
    var plan: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).foregroundStyle(.secondary)
                Text(label).font(.headline)
                Spacer()
                if let resetsAt = cat.resetsAt {
                    Label("\(resetsAt, style: .relative)", systemImage: "arrow.clockwise")
                        .font(.caption).foregroundStyle(.tertiary).labelStyle(.titleAndIcon)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(UsageFormat.tokens(cat.tokens))
                    .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                Text("tokens").font(.title3).foregroundStyle(.secondary)
                Spacer()
                if cat.cost > 0 {
                    Text(UsageFormat.cost(cat.cost))
                        .font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                }
            }

            if cat.utilization != nil {
                UsageBar(utilization: cat.utilization!, height: 16)
                HStack {
                    if let cap = limitCaption(cat, plan: plan) {
                        Text(cap).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let eta = etaText(cat, burnPerSec: burnPerSec) {
                        Text(eta).font(.caption).foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("Set a weekly limit in Settings to see a percentage")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .card()
    }
}

private struct StatCard: View {
    let label: String
    let sublabel: String
    let systemImage: String
    let cat: CategoryData
    var burnPerSec: Double = 0
    var plan: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).foregroundStyle(.secondary).font(.caption)
                Text(label).font(.subheadline.weight(.semibold))
                Text(sublabel).font(.caption).foregroundStyle(.tertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(UsageFormat.tokens(cat.tokens))
                    .font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                Text("tok").font(.caption).foregroundStyle(.secondary)
            }
            if cat.cost > 0 {
                Text(UsageFormat.cost(cat.cost)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if cat.utilization != nil {
                UsageBar(utilization: cat.utilization!, height: 10)
                if let cap = limitCaption(cat, plan: plan) {
                    Text(cap).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                if let eta = etaText(cat, burnPerSec: burnPerSec) {
                    Text(eta).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            if let resetsAt = cat.resetsAt {
                Text("resets \(resetsAt, style: .relative)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .card()
    }
}

// MARK: - Projects

private struct ProjectsSection: View {
    let projects: ProjectBreakdown?
    var body: some View {
        if let projects, !projects.entries.isEmpty {
            List {
                Section("Top projects · last 7 days") {
                    ForEach(projects.topN(30)) { entry in
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.tint).font(.body)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.displayName).font(.body)
                                Text(entry.path).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(UsageFormat.tokens(entry.tokens)) tok").monospacedDigit()
                                Text(UsageFormat.cost(entry.cost))
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } else {
            ContentUnavailableView("No activity yet",
                                   systemImage: "folder",
                                   description: Text("Usage appears here once you've used Claude Code in the last 7 days."))
        }
    }
}

// MARK: - Setup

private struct SetupGuide: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 44)).foregroundStyle(.orange)
            Text("Setup required").font(.title2.bold())
            Text("Claude Rate Widget reads `~/.claude/projects/` on this Mac to compute your usage. We'll request permission once.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            Button("Grant access") { HomeAccessPrompter.shared.prompt() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}
