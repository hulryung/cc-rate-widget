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
            // Menu-bar title: compact 5h/7d percentages, e.g. "2%/22%".
            var parts: [String] = []
            if let u = rate.session.utilization { parts.append("\(Int(u * 100))%") }
            if let u = rate.weekly.utilization  { parts.append("\(Int(u * 100))%") }
            button.title = parts.isEmpty
                ? " \(UsageFormat.tokens(rate.session.tokens))"   // no %: fall back to tokens
                : " " + parts.joined(separator: "/")
        } else {
            button.title = " Claude"
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

    private func usageItem(_ label: String, _ cat: CategoryData) -> NSMenuItem {
        let font = NSFont.menuFont(ofSize: 13)
        let bold = NSFont.boldSystemFont(ofSize: 13)
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "\(label)   ",
                                    attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: font]))
        if let u = cat.utilization {
            s.append(NSAttributedString(string: "\(Int(u * 100))%  ",
                                        attributes: [.foregroundColor: pctColor(u), .font: bold]))
        }
        s.append(NSAttributedString(string: "\(UsageFormat.tokens(cat.tokens)) tok",
                                    attributes: [.foregroundColor: NSColor.labelColor, .font: font]))
        var tail = ""
        if cat.cost > 0 { tail += "  ·  \(UsageFormat.cost(cat.cost))" }
        if let reset = cat.resetsAt { tail += "  ·  resets in \(UsageFormat.remainingCoarse(until: reset))" }
        if !tail.isEmpty {
            s.append(NSAttributedString(string: tail,
                                        attributes: [.foregroundColor: NSColor.tertiaryLabelColor, .font: font]))
        }
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = s
        item.isEnabled = true
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

    private func pctColor(_ u: Double) -> NSColor {
        if u >= 1.0 { return .systemRed }
        if u >= 0.8 { return .systemOrange }
        return .systemGreen
    }

    // MARK: - Actions

    @objc private func refreshAction() { AggregationCoordinator.shared.runOnce() }

    @objc private func openAction() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first { window.makeKeyAndOrderFront(nil) }
    }

    @objc private func quitAction() { NSApp.terminate(nil) }
}
