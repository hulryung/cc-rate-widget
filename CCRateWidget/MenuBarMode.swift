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

    func installIfEnabled() {
        guard SettingsStore.shared.menuBarEnabled else { return }
        install()
    }

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

    func remove() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        cancellable = nil
        closePopover()
    }

    // MARK: - Title

    private func update(_ rate: RateData?) {
        guard let button = statusItem?.button else { return }
        guard let rate, rate.status != .noLocalData else {
            button.attributedTitle = NSAttributedString(string: "")
            return
        }
        // One labelled number. Two unlabelled percentages ("2%/22%") made the reader
        // remember which came first; the weekly window is the one worth a glance.
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

        let content = UsagePopover(
            onOpenWindow: { [weak self] in
                self?.closePopover()
                MenuBarMode.openMainWindow()
            },
            onDismiss: { [weak self] in self?.closePopover() }
        )

        let p = NSPopover()
        p.contentViewController = NSHostingController(rootView: content)
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
        let open = NSMenuItem(title: "Open Window", action: #selector(openAction), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)
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

    static func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func refreshAction() { AggregationCoordinator.shared.runOnce() }
    @objc private func openAction() { MenuBarMode.openMainWindow() }
    @objc private func quitAction() { NSApp.terminate(nil) }
    @objc private func settingsAction() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
