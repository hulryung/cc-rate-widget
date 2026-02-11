import SwiftUI

@main
struct CCRateWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 480, height: 400)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        syncCredentials()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        syncCredentials()
    }

    private func syncCredentials() {
        if let cred = CredentialManager.shared.readCredentialsFromDisk() {
            CredentialManager.shared.syncToAppGroup(cred)
        }
    }
}
