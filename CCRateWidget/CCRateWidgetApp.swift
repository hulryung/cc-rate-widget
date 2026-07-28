import SwiftUI

/// A menu-bar app. There is no main window: the popover and the ⌥⌘U HUD show the same
/// summary, and everything the window used to carry — including the project breakdown —
/// lives in the popover now. Keeping a window alive alongside them meant a hide-vs-destroy
/// dance, an activation-policy switch, and a launch-time race to attach a close handler,
/// all to maintain a surface that duplicated the popover.
///
/// Settings is a window this app creates itself — see `SettingsWindowController`.
@main
struct CCRateWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// `App` requires a scene, but this app has no SwiftUI-managed windows: the status
    /// item, popover, HUD, and Settings window are all created directly. This placeholder
    /// is unreachable — opening it needs the app menu, which an `LSUIElement` app lacks.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            AggregationCoordinator.shared.start()
            MenuBarMode.shared.install()
            UsageHUD.shared.registerHotKeyIfEnabled()
        }
    }

    /// The Settings window closing must not take the app with it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
