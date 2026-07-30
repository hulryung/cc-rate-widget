import SwiftUI

/// What ⌥⌘U shows. Deliberately not the popover.
///
/// The popover is something you browse — cards, per-project totals, buttons. The HUD is on
/// screen for five seconds, so it answers only the three questions worth asking at a
/// glance: how much is used, how long until it resets, and when that reset lands.
/// Token and dollar totals stay, but demoted.
struct UsageHUDView: View {
    @ObservedObject var coordinator = AggregationCoordinator.shared
    var cornerRadius: CGFloat = 18
    /// Drives the entrance. A panel that simply exists on the next frame is easy to miss;
    /// something that grows into place is not.
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.group) {
            if let rate = coordinator.lastSnapshot, rate.status != .noLocalData, !rate.windows.isEmpty {
                // However many Anthropic reports — the scoped per-model windows ("Fable")
                // appear and disappear, so the list is theirs, not ours.
                ForEach(Array(rate.windows.enumerated()), id: \.element.id) { index, w in
                    if index > 0 { Divider() }
                    WindowBlock(window: w, prominent: index == 0)
                }

                HStack(spacing: Metric.gutter) {
                    if let plan = rate.planName {
                        Text(plan)
                    }
                    Text(rate.source.shortLabel)
                    Spacer()
                    Text("Updated \(rate.fetchedAt, style: .time)")
                }
                .font(HUDType.micro)
                .foregroundStyle(.tertiary)
            } else {
                Label("No usage data yet", systemImage: "folder.badge.questionmark")
                    .font(HUDType.title)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .padding(Metric.screen)
        .frame(width: 400)
        // A translucent material, not a flat window colour. This is what macOS itself uses
        // for transient HUDs (Spotlight, the volume overlay), and it reads as floating
        // *above* the screen rather than as one more window that happens to be in front.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            // Critically damped on purpose: the panel is sized to its content, so an
            // overshoot past 1.0 would clip against its own edges.
            withAnimation(.spring(response: 0.28, dampingFraction: 1.0)) { appeared = true }
        }
    }
}

/// One rolling window: the percentage, then how long is left, then when it resets.
private struct WindowBlock: View {
    let window: UsageWindow
    /// The first window — weekly, what people plan around — gets the large numeral.
    let prominent: Bool
    private var cat: CategoryData { window.data }

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.gutter) {
            HStack(spacing: Metric.gutter) {
                Text(window.title).font(HUDType.title)
                Text(window.subtitle).font(HUDType.micro).foregroundStyle(.tertiary)
                Spacer()
                // Demoted: still available, but not what the eye lands on first.
                if cat.tokens > 0 {
                    Text(UsageFormat.tokens(cat.tokens) + " tok")
                        .font(HUDType.detail).foregroundStyle(.secondary)
                }
                if cat.cost > 0 {
                    Text(UsageFormat.cost(cat.cost))
                        .font(HUDType.detail).foregroundStyle(.tertiary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: Metric.group) {
                if let u = cat.utilization {
                    Text("\(Int(u * 100))%")
                        .font(prominent ? HUDType.percent : HUDType.remaining)
                        .foregroundStyle(UsageLevel(u).textTint)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.2), value: u)
                } else {
                    Text(UsageFormat.tokens(cat.tokens))
                        .font(prominent ? HUDType.percent : HUDType.remaining)
                }

                if let resetsAt = cat.resetsAt {
                    VStack(alignment: .leading, spacing: 1) {
                        // The answer to "do I need to slow down right now".
                        Text(UsageFormat.remainingCoarse(until: resetsAt) + " left")
                            .font(HUDType.remaining)
                        Text("resets " + UsageFormat.resetMoment(resetsAt))
                            .font(HUDType.micro)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if let u = cat.utilization {
                UsageBar(utilization: u, height: prominent ? Metric.barHeight : Metric.barHeightSlim,
                         animated: true)
            }
        }
    }
}
