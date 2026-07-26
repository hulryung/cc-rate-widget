import SwiftUI

/// The single usage bar used by the app window and every widget size.
///
/// Previously the app and the widget each had their own copy with different heights,
/// different fills, and different rounding, so the same number looked like two things.
struct UsageBar: View {
    let utilization: Double          // 0…1+, clamped for display
    var height: CGFloat = Metric.barHeight
    var animated: Bool = false       // app only — widget timelines gain nothing from motion

    var body: some View {
        let u = max(0, utilization)
        let clamped = min(u, 1.0)
        let level = UsageLevel(u)

        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(level.tint)
                    // No minimum-width floor: 0% has to render as genuinely empty,
                    // otherwise idle looks identical to barely-started.
                    .frame(width: geo.size.width * clamped)
            }
        }
        .frame(height: height)
        .animation(animated ? .easeOut(duration: 0.2) : nil, value: clamped)
        .accessibilityElement()
        .accessibilityLabel("Usage")
        .accessibilityValue("\(Int(u * 100)) percent of limit, \(level.word)")
    }
}

/// A percentage rendered as a chip. Carries the level's word so the meaning is never
/// conveyed by hue alone.
struct UsageChip: View {
    let utilization: Double
    var body: some View {
        let level = UsageLevel(utilization)
        Text("\(Int(utilization * 100))%")
            .font(AppType.label)
            .monospacedDigit()
            .padding(.horizontal, Metric.tight)
            .padding(.vertical, 2)
            .background(Capsule().fill(level.chipFill))
            .foregroundStyle(level.tint)
            .accessibilityLabel("\(Int(utilization * 100)) percent used, \(level.word)")
    }
}
