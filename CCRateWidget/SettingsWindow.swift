import AppKit
import SwiftUI

/// Owns the Settings window directly instead of going through SwiftUI's `Settings` scene.
///
/// That scene is opened by sending `showSettingsWindow:` through the responder chain, which
/// relies on the app menu SwiftUI installs. An `LSUIElement` app has no app menu, so the
/// action finds no target and nothing happens — with no main window and no menu bar menu,
/// that left Settings unreachable entirely.
///
/// A window we create ourselves has no such dependency.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    private override init() { super.init() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView().frame(width: 480))
        let w = NSWindow(contentViewController: hosting)
        w.title = "Settings"
        w.styleMask = [.titled, .closable]
        // Closing must not deallocate it — the status item reopens the same window.
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
    }
}
