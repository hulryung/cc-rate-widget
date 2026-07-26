import SwiftUI

/// The usage cards, shared by the main window, the menu-bar popover, and the hotkey HUD.
/// One definition so the three surfaces can't drift apart.

// MARK: - Hero

/// Weekly usage — the number worth planning around, so it gets the largest slot.
struct HeroCard: View {
    let cat: CategoryData
    var plan: String? = nil
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Metric.tight : Metric.group) {
            HStack(spacing: Metric.gutter) {
                Text("Weekly").font(AppType.title)
                Text("7 days").font(AppType.detail).foregroundStyle(.tertiary)
                Spacer()
                if let plan { PlanPill(plan) }
                if let u = cat.utilization { UsageChip(utilization: u) }
            }

            HStack(alignment: .firstTextBaseline, spacing: Metric.tight) {
                Text(UsageFormat.tokens(cat.tokens))
                    .font(compact ? AppType.metric : AppType.hero)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: cat.tokens)
                Text("tok").font(AppType.detail).foregroundStyle(.secondary)
                Spacer()
                if cat.cost > 0 {
                    Text(UsageFormat.cost(cat.cost))
                        .font(compact ? AppType.value : AppType.metric)
                        .foregroundStyle(.secondary)
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

// MARK: - Stat

struct StatCard: View {
    let label: String
    let window: String
    let cat: CategoryData
    var plan: String? = nil
    /// Suppressed when this card's reset is the same instant as the hero's — repeating
    /// "Sun, Jul 26 at 10 PM · 1h left" under all three cards is noise, not information.
    var showsReset: Bool = true

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

            if showsReset, let resetsAt = cat.resetsAt {
                ResetLine(date: resetsAt)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .usageCard()
    }
}

// MARK: - Small parts

struct PlanPill: View {
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
struct ResetLine: View {
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
struct FooterLine: View {
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
func limitCaption(_ cat: CategoryData, plan: String?) -> String? {
    guard let kind = cat.limitKind, cat.utilization != nil else { return nil }
    switch kind {
    case .official:
        return plan.map { "Anthropic quota · \($0)" } ?? "Anthropic quota"
    case .userLimit:
        guard let limit = cat.limitTokens else { return nil }
        return "of \(UsageFormat.tokens(limit)) tok limit"
    case .typicalPeak:
        guard let limit = cat.limitTokens else { return nil }
        return "of your typical peak (\(UsageFormat.tokens(limit)) tok)"
    }
}

// MARK: - The shared usage body

/// The three cards plus footer, used by every surface. `compact` tightens it for the
/// popover and HUD, where vertical space is scarcer than in the window.
struct UsageSummary: View {
    let rate: RateData
    var compact: Bool = false

    var body: some View {
        // Sonnet shares the weekly window, so its reset instant is the hero's. Show it once.
        let sonnetSharesReset = rate.weeklySonnet.resetsAt == rate.weekly.resetsAt

        VStack(alignment: .leading, spacing: compact ? Metric.group : Metric.section) {
            HeroCard(cat: rate.weekly, plan: rate.planName, compact: compact)
            HStack(alignment: .top, spacing: compact ? Metric.group : Metric.section) {
                StatCard(label: "Session", window: "5 hours", cat: rate.session, plan: rate.planName)
                StatCard(label: "Sonnet", window: "7 days", cat: rate.weeklySonnet, plan: rate.planName,
                         showsReset: !sonnetSharesReset)
            }
            .fixedSize(horizontal: false, vertical: true)   // equal heights
            FooterLine(rate: rate)
        }
    }
}
