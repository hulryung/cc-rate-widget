import SwiftUI

/// Contents of the menu-bar popover and the hotkey HUD — the app's only real surface.
///
/// Both are transient: they appear, get read, and dismiss. So this is the summary, the
/// project breakdown that used to justify a separate window, and the two actions worth
/// reaching for from a glance.
struct UsagePopover: View {
    @ObservedObject var coordinator = AggregationCoordinator.shared
    @State private var projects: ProjectBreakdown?
    var onDismiss: () -> Void = {}
    /// The HUD floats on a clear panel and has to round its own corners; the popover is
    /// already clipped by its chrome.
    var cornerRadius: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.group) {
            if let rate = coordinator.lastSnapshot, rate.status != .noLocalData, !rate.windows.isEmpty {
                UsageSummary(rate: rate, compact: true)
                if let projects, !projects.entries.isEmpty {
                    Divider()
                    ProjectsList(projects: projects)
                }
            } else if coordinator.lastSnapshot?.status == .noLocalData {
                ContentUnavailableView {
                    Label("Setup required", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("Grant access to ~/.claude to start tracking.")
                } actions: {
                    Button("Grant Access") { HomeAccessPrompter.shared.prompt() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(height: 180)
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }

            Divider()

            HStack(spacing: Metric.tight) {
                Button {
                    AggregationCoordinator.shared.runOnce()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("r", modifiers: .command)

                Spacer()

                Button("Settings…") {
                    onDismiss()
                    MenuBarMode.openSettings()
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(",", modifiers: .command)
            }
            .font(AppType.detail)
        }
        .padding(Metric.section)
        .frame(width: 400)
        // Paint our own opaque surface rather than letting the popover's vibrant chrome
        // show through. Relying on the chrome meant the cards resolved their colours
        // against a different appearance than the surrounding material, so white cards
        // sat on a dark popover and the footer text vanished into it.
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: coordinator.lastSnapshot?.fetchedAt) {
            projects = try? LocalStore.shared.readProjects()
        }
    }
}

/// The per-project breakdown, previously the main window's only unique content.
/// Scrolls past a handful of rows so a busy week doesn't make the popover tower.
private struct ProjectsList: View {
    let projects: ProjectBreakdown

    var body: some View {
        let top = projects.topN(20)
        let maxTokens = max(top.first?.tokens ?? 1, 1)

        VStack(alignment: .leading, spacing: Metric.tight) {
            Text("Projects · last 7 days")
                .font(AppType.label).foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: Metric.gutter) {
                    ForEach(top) { entry in
                        HStack(spacing: Metric.tight) {
                            Text(entry.displayName)
                                .font(AppType.detail)
                                .lineLimit(1).truncationMode(.middle)
                                .frame(width: 120, alignment: .leading)
                                .help(entry.path)

                            // Relative bar: comparing projects to each other is the point,
                            // so scale against the largest rather than a usage limit.
                            GeometryReader { geo in
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.35))
                                    .frame(width: geo.size.width * CGFloat(entry.tokens) / CGFloat(maxTokens))
                            }
                            .frame(height: 5)

                            Text(UsageFormat.tokens(entry.tokens))
                                .font(AppType.micro).monospacedDigit()
                                .frame(width: 52, alignment: .trailing)
                            Text(UsageFormat.cost(entry.cost))
                                .font(AppType.micro).foregroundStyle(.secondary).monospacedDigit()
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                }
            }
            // Roughly seven rows before it scrolls — enough that most weeks need no
            // scrolling, without the popover growing to fill the screen.
            .frame(maxHeight: 150)
        }
    }
}
