import AppKit
import SwiftUI
import Combine

/// The status-bar item: a live percentage you can read without clicking, and a popover
/// with the full summary when you do.
///
/// This replaced an NSMenu of attributed text rows. A popover can host the same SwiftUI
/// cards the main window uses, so the two surfaces stay identical by construction rather
/// than by a second hand-maintained AppKit rendering of the same numbers.
@MainActor
final class MenuBarMode {
    static let shared = MenuBarMode()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellable: AnyCancellable?
    private var dismissMonitor: Any?

    private init() {}

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent",
                                     accessibilityDescription: "Claude usage")
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        update(AggregationCoordinator.shared.lastSnapshot)
        cancellable = AggregationCoordinator.shared.$lastSnapshot.sink { [weak self] rate in
            Task { @MainActor in self?.update(rate) }
        }
    }


    // MARK: - Title

    private func update(_ rate: RateData?) {
        guard let button = statusItem?.button else { return }
        guard let rate, rate.status != .noLocalData, let weekly = rate.weekly?.data else {
            button.attributedTitle = NSAttributedString(string: "")
            return
        }
        // One labelled number. Two unlabelled percentages ("2%/22%") made the reader
        // remember which came first; the weekly window is the one worth a glance.
        if let u = weekly.utilization {
            button.attributedTitle = NSAttributedString(
                string: " \(Int(u * 100))%",
                attributes: [
                    .foregroundColor: UsageLevel(u).nsColor,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                ])
        } else {
            button.attributedTitle = NSAttributedString(
                string: " \(UsageFormat.tokens(weekly.tokens))",
                attributes: [
                    .foregroundColor: NSColor.labelColor,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                ])
        }
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        if popover?.isShown == true {
            closePopover()
            return
        }
        // A right-click still gets a menu, for quit / settings, which a popover shouldn't own.
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }

        let content = UsagePopover(onDismiss: { [weak self] in self?.closePopover() })

        let hosting = NSHostingController(rootView: content)
        // Pin the appearance explicitly. Without this the hosted view can resolve its
        // colours against an appearance that differs from the popover chrome, which
        // showed up as light cards inside a dark popover until the next redraw.
        hosting.view.appearance = NSApp.effectiveAppearance

        let p = NSPopover()
        p.contentViewController = hosting
        p.appearance = NSApp.effectiveAppearance
        p.behavior = .transient          // dismisses when you click away — the "disappears" part
        p.animates = true
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover = p

        // .transient alone doesn't catch Esc, which is the reflex for dismissing a HUD.
        dismissMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {     // Esc
                self?.closePopover()
                return nil
            }
            return event
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        popover = nil
        if let dismissMonitor { NSEvent.removeMonitor(dismissMonitor) }
        dismissMonitor = nil
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshAction), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil          // restore click-to-popover for the next left click
    }

    // MARK: - Actions

    /// The status item and the popover are the only routes to Settings in an accessory
    /// app, so this has to work without a menu to route through.
    static func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func refreshAction() { AggregationCoordinator.shared.runOnce() }
    @objc private func quitAction() { NSApp.terminate(nil) }
    @objc private func settingsAction() { MenuBarMode.openSettings() }
}
