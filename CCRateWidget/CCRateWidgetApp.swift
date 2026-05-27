import SwiftUI
#if canImport(UserNotifications)
import UserNotifications
#endif

@main
struct CCRateWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Claude Rate Widget", id: "main") {
            ContentView()
                .task { await requestNotificationsIfNeeded() }
        }
        .defaultSize(width: 560, height: 440)
    }

    private func requestNotificationsIfNeeded() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        #endif
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            AggregationCoordinator.shared.start()
            MenuBarMode.shared.installIfEnabled()
        }
    }
}
