import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Design tokens shared by the app window, the menu bar, and all three widget sizes.
///
/// Lives in Shared/ because `project.yml` compiles that directory into every target, so
/// the sandboxed widget extension and the app resolve identical values. Before this
/// existed, the usage-colour thresholds were written out three separate times and had
/// already begun to drift.
///
/// The scale follows the conventions the sibling apps agree on: semantic system colours,
/// a hairline of `separatorColor` at 0.5pt, `controlBackgroundColor` surfaces, and
/// hardcoded point sizes reserved for SF Symbol glyphs rather than text.

// MARK: - Spacing & geometry

enum Metric {
    static let gutter:  CGFloat = 6    // label → its content
    static let tight:   CGFloat = 8    // inside a group
    static let group:   CGFloat = 12   // between groups in a card
    static let section: CGFloat = 16   // between cards; also card inset
    static let screen:  CGFloat = 20   // window inset

    static let cardRadius: CGFloat = 10
    static let chipRadius: CGFloat = 6
    static let hairline:   CGFloat = 0.5

    static let barHeight: CGFloat = 8

    // Widgets run to a tighter budget than the window.
    static let widgetBar:   CGFloat = 6
    static let widgetTight: CGFloat = 4
    static let widgetGroup: CGFloat = 8
}

// MARK: - Type ramps

/// App-window type. Semantic styles so Dynamic Type still applies; `.rounded` is spent on
/// exactly one role per surface — the hero number — so it stays a signal rather than decoration.
enum AppType {
    static let hero   = Font.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit()
    static let metric = Font.system(.title2, design: .rounded).weight(.semibold).monospacedDigit()
    static let title  = Font.headline
    static let value  = Font.body.monospacedDigit()
    static let label  = Font.caption.weight(.semibold)
    static let detail = Font.caption
    static let micro  = Font.caption2.weight(.medium)
}

/// Widget type. Fixed sizes are deliberate here: widgets have a hard space budget and do
/// not participate in Dynamic Type. Four steps with perceptible gaps; nothing below 10pt.
enum WidgetType {
    static let hero  = Font.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()
    static let value = Font.system(size: 15, weight: .semibold).monospacedDigit()
    static let label = Font.system(size: 12, weight: .medium)
    static let micro = Font.system(size: 10)
}

// MARK: - Usage level

/// The one place utilization becomes a colour.
///
/// Resting state is intentionally neutral rather than green: a dashboard that is saturated
/// while nothing is wrong has no headroom left to signal that something *is* wrong.
enum UsageLevel {
    case normal, warning, over

    init(_ utilization: Double) {
        if utilization >= 1.0      { self = .over }
        else if utilization >= 0.8 { self = .warning }
        else                       { self = .normal }
    }

    /// Fill colour — bars and other shapes, where a large area carries a muted tone fine.
    var tint: Color {
        switch self {
        case .normal:  return .secondary
        case .warning: return .orange
        case .over:    return .red
        }
    }

    /// Text colour. Small type needs more contrast than a filled shape, so the resting
    /// state is full-strength `.primary` — neutral means no hue, not low contrast.
    var textTint: Color {
        switch self {
        case .normal:  return .primary
        case .warning: return .orange
        case .over:    return .red
        }
    }

    /// Alpha decreases as the hue gets louder, so all three chips carry equal visual weight.
    var chipFill: Color {
        switch self {
        case .normal:  return Color.secondary.opacity(0.20)
        case .warning: return Color.orange.opacity(0.18)
        case .over:    return Color.red.opacity(0.16)
        }
    }

    /// Text backing for the colour, so the signal survives for colour-blind users and VoiceOver.
    var word: String {
        switch self {
        case .normal:  return "OK"
        case .warning: return "Near limit"
        case .over:    return "Over limit"
        }
    }

    #if canImport(AppKit)
    /// For the menu bar, where the number must stay legible against a busy bar at 12pt.
    /// Normal is `labelColor`, not `secondaryLabelColor`: the point of the resting state
    /// is to carry no *hue*, so warning and over have somewhere to stand out from —
    /// not to be faint. Secondary label reads as washed-out grey up there.
    var nsColor: NSColor {
        switch self {
        case .normal:  return .labelColor
        case .warning: return .systemOrange
        case .over:    return .systemRed
        }
    }
    #endif
}

// MARK: - Status

extension OverallStatus {
    /// nil when healthy. Rendering nothing for the normal case keeps the indicator
    /// meaningful — a dot that is always present is a dot nobody reads.
    var indicator: (color: Color, symbol: String, label: String)? {
        switch self {
        case .active:
            return nil
        case .warning, .notLoggedIn:
            return (.orange, "exclamationmark.triangle.fill", label)
        case .rateLimited, .unauthorized, .forbidden:
            return (.red, "xmark.octagon.fill", label)
        case .error, .unknown, .noLocalData:
            return (.secondary, "questionmark.circle.fill", label)
        }
    }
}

extension RateDataSource {
    /// Lowercase prose for a footer line, rather than a shouty corner badge.
    var shortLabel: String {
        switch self {
        case .jsonl:       return "local logs"
        case .oauth:       return "official"
        case .hybrid:      return "local + official"
        case .partial:     return "still learning"
        case .noLocalData: return "not set up"
        }
    }
}

// MARK: - Surface

extension View {
    /// The card treatment: `controlBackgroundColor` fill with a true hairline border.
    func usageCard() -> some View {
        self
            .padding(Metric.section)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: Metric.hairline))
    }
}
