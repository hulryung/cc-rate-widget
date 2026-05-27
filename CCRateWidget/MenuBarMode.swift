import AppKit
import SwiftUI

@MainActor
final class MenuBarMode {
    static let shared = MenuBarMode()
    private var statusItem: NSStatusItem?

    private init() {}

    func installIfEnabled() {
        guard SettingsStore.shared.menuBarEnabled else { return }
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "CC"
        let menu = NSMenu()

        let refresh = NSMenuItem(title: "Refresh now",
                                  action: #selector(refreshAction),
                                  keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

        let open = NSMenuItem(title: "Open main window",
                              action: #selector(openAction),
                              keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        let quit = NSMenuItem(title: "Quit",
                              action: #selector(quitAction),
                              keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func refreshAction() {
        AggregationCoordinator.shared.runOnce()
    }

    @objc private func openAction() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first { window.makeKeyAndOrderFront(nil) }
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
