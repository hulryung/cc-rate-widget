import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store = SettingsStore.shared
    @State private var showRelaunchPrompt = false

    var body: some View {
        Form {
            Section("Usage") {
                Text("Claude Rate Widget reports the tokens and cost recorded in your local Claude Code logs. It does not estimate Anthropic's quota percentage — that requires the official API.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Background") {
                Toggle("Run in menu bar (recommended for alerts)", isOn: $store.menuBarEnabled)
                    .onChange(of: store.menuBarEnabled) { _, _ in showRelaunchPrompt = true }
                Text("Required for notifications to fire even when the main window is closed.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Anthropic OAuth (optional)") {
                Toggle("Pull official quota when available", isOn: $store.oauthEnabled)
                    .disabled(true)
                Text("Coming in a later release. Off and inert in 1.7 — the widget runs entirely on local JSONL data.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Data") {
                Button("Re-prompt for ~/.claude access") {
                    HomeAccessPrompter.shared.prompt()
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .alert("Menu bar setting saved", isPresented: $showRelaunchPrompt) {
            Button("Quit and reopen") { NSApplication.relaunchApp() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Menu bar mode setting saved. The Dock icon will remain visible — relaunching is only needed to attach (or detach) the menu-bar item this session.")
        }
    }
}

extension NSApplication {
    @objc static func relaunchApp() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

