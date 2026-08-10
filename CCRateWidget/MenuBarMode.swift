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
    private var outsideClickMonitor: Any?
    private var resignObserver: Any?

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

        // Take focus before showing. An accessory app doesn't activate when its status item
        // is clicked, and a *local* event monitor only sees events routed to this app — so
        // Esc, ⌘R and ⌘, were all dead until you had clicked into the popover, which
        // activated the app as a side effect. The popover is a surface you interact with, so
        // taking focus is the right trade; the ⌥⌘U HUD is a glance and deliberately doesn't.
        //
        // The forceful variant, matching SettingsWindowController: cooperative `activate()`
        // may decline when the system thinks another app should keep focus, and a decline
        // here is silent and leaves the shortcuts dead again. This is the call already known
        // to activate this LSUIElement app.
        NSApp.activate(ignoringOtherApps: true)

        let p = NSPopover()
        p.contentViewController = hosting
        p.appearance = NSApp.effectiveAppearance
        // Not .transient. Now that the app activates, .transient would close the popover on
        // the mouse-down over our own status item — and then the button's action would fire
        // against an already-closed popover and reopen it on that same click. Owning every
        // dismissal path below keeps that race from existing.
        p.behavior = .applicationDefined
        p.animates = true
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover = p

        // Esc, and clicks on our own other windows (Settings). The status item is excluded
        // deliberately: togglePopover already closes on a second click, and closing here
        // too would let that same click fall through and reopen the popover.
        dismissMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 {     // Esc
                    self.closePopover()
                    return nil
                }
                return event
            }
            if event.window !== self.statusItem?.button?.window,
               event.window !== self.popover?.contentViewController?.view.window {
                self.closePopover()
            }
            return event
        }

        // Clicks in *other* apps and on the desktop. A global monitor sees only events
        // delivered elsewhere, so it can never observe — and thus never double-handle — a
        // click on our own status item. Mouse events need no Accessibility permission; only
        // keyboard monitoring does, which is why the ⌥⌘U hotkey goes through Carbon.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }

        // Losing focus without a click at all — ⌘-Tab, Mission Control, a lock screen.
        // Without this, .applicationDefined would leave the popover stranded on screen.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        popover = nil
        if let dismissMonitor { NSEvent.removeMonitor(dismissMonitor) }
        dismissMonitor = nil
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshAction), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil          // restore click-to-popover for the next left click
    }

    // MARK: - Actions

    @objc private func refreshAction() { AggregationCoordinator.shared.runOnce() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}
