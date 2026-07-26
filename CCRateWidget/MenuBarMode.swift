import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarMode {
    static let shared = MenuBarMode()
    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?

    private init() {}

    func installIfEnabled() {
        guard SettingsStore.shared.menuBarEnabled else { return }
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent",
                                     accessibilityDescription: "Claude usage")
        item.button?.imagePosition = .imageLeading
        statusItem = item

        update(AggregationCoordinator.shared.lastSnapshot)
        cancellable = AggregationCoordinator.shared.$lastSnapshot.sink { [weak self] rate in
            Task { @MainActor in self?.update(rate) }
        }
    }

    // MARK: - Rendering

    private func update(_ rate: RateData?) {
        guard let item = statusItem, let button = item.button else { return }
        if let rate, rate.status != .noLocalData {
            // One labelled number. "2%/22%" was two unlabelled figures the user had to
            // remember the order of; the weekly window is the one worth a glance.
            if let u = rate.weekly.utilization {
                button.attributedTitle = NSAttributedString(
                    string: " \(Int(u * 100))%",
                    attributes: [
                        .foregroundColor: UsageLevel(u).nsColor,
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    ])
            } else {
                button.attributedTitle = NSAttributedString(
                    string: " \(UsageFormat.tokens(rate.weekly.tokens))",
                    attributes: [
                        .foregroundColor: NSColor.labelColor,
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                    ])
            }
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
        item.menu = buildMenu(rate)
    }

    private func buildMenu(_ rate: RateData?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false   // keep info rows readable (not auto-grayed)

        if let rate, rate.status != .noLocalData {
            menu.addItem(header(rate.source == .oauth ? "OFFICIAL USAGE" : "USAGE"))
            menu.addItem(usageItem("Session · 5h", rate.session))
            menu.addItem(usageItem("Weekly · 7d", rate.weekly))
            menu.addItem(usageItem("Sonnet · 7d", rate.weeklySonnet))
            menu.addItem(.separator())
        } else if rate?.status == .noLocalData {
            menu.addItem(header("Setup required — open the app"))
            menu.addItem(.separator())
        }

        let refresh = NSMenuItem(title: "Refresh now", action: #selector(refreshAction), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open main window", action: #selector(openAction), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)
        let quit = NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    /// Columns are aligned with real tab stops rather than padded spaces, so the
    /// percentages and token counts line up regardless of digit count.
    private func usageItem(_ label: String, _ cat: CategoryData) -> NSMenuItem {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let bold = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)

        let style = NSMutableParagraphStyle()
        style.tabStops = [
            NSTextTab(textAlignment: .right, location: 116),   // percentage
            NSTextTab(textAlignment: .right, location: 186),   // tokens
            NSTextTab(textAlignment: .right, location: 246),   // cost
        ]

        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: label,
                                    attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: font]))

        if let u = cat.utilization {
            s.append(NSAttributedString(string: "\t\(Int(u * 100))%",
                                        attributes: [.foregroundColor: UsageLevel(u).nsColor, .font: bold]))
        } else {
            s.append(NSAttributedString(string: "\t—",
                                        attributes: [.foregroundColor: NSColor.tertiaryLabelColor, .font: font]))
        }

        s.append(NSAttributedString(string: "\t\(UsageFormat.tokens(cat.tokens)) tok",
                                    attributes: [.foregroundColor: NSColor.labelColor, .font: font]))

        if cat.cost > 0 {
            s.append(NSAttributedString(string: "\t\(UsageFormat.cost(cat.cost))",
                                        attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: font]))
        }

        s.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: s.length))

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = s
        item.isEnabled = true
        if let reset = cat.resetsAt {
            item.toolTip = "Resets \(UsageFormat.resetMoment(reset)) · \(UsageFormat.remainingCoarse(until: reset)) left"
        }
        return item
    }

    private func header(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
        ])
        item.isEnabled = true
        return item
    }

    // MARK: - Actions

    @objc private func refreshAction() { AggregationCoordinator.shared.runOnce() }

    @objc private func openAction() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first { window.makeKeyAndOrderFront(nil) }
    }

    @objc private func quitAction() { NSApp.terminate(nil) }
}
