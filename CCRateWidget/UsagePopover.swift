import SwiftUI

/// Contents of the menu-bar popover and the hotkey HUD.
///
/// Both surfaces are transient: they appear, get read in a second or two, and dismiss.
/// So this is the summary plus the two actions worth reaching for from a glance, and
/// nothing else — anything deeper belongs in the main window.
struct UsagePopover: View {
    @ObservedObject var coordinator = AggregationCoordinator.shared
    var onOpenWindow: () -> Void = {}
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.group) {
            if let rate = coordinator.lastSnapshot, rate.status != .noLocalData {
                UsageSummary(rate: rate, compact: true)
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

                Button("Open Window") { onOpenWindow() }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("o", modifiers: .command)
            }
            .font(AppType.detail)
        }
        .padding(Metric.section)
        .frame(width: 380)
    }
}
