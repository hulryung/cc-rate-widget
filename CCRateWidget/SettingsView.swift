import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store = SettingsStore.shared
    @State private var showRelaunchPrompt = false

    var body: some View {
        Form {
            Section {
                Text("Claude Rate Widget reports the tokens and cost recorded in your local Claude Code logs.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("Usage")
            }

            Section {
                LabeledContent("5-hour limit") {
                    limitField($store.fiveHourLimitMillions)
                }
                LabeledContent("Weekly limit") {
                    limitField($store.weeklyLimitMillions)
                }
            } header: {
                Text("Percentage (optional)")
            } footer: {
                Text("Enter your plan's token limits (in millions) to show a percentage. Leave at 0 to show absolute usage only. Local logs can't read Anthropic's official quota %, so this is measured against the limit you provide.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .onChange(of: store.fiveHourLimitMillions) { _, _ in AggregationCoordinator.shared.runOnce() }
            .onChange(of: store.weeklyLimitMillions) { _, _ in AggregationCoordinator.shared.runOnce() }

            Section {
                Toggle("Run in menu bar", isOn: $store.menuBarEnabled)
                    .onChange(of: store.menuBarEnabled) { _, _ in showRelaunchPrompt = true }
            } header: {
                Text("Background")
            } footer: {
                Text("Keeps the app alive so it can refresh and (later) fire notifications even when the window is closed.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show official usage % (matches Claude /status)", isOn: $store.oauthEnabled)
                    .onChange(of: store.oauthEnabled) { _, _ in AggregationCoordinator.shared.runOnce() }
            } header: {
                Text("Official usage")
            } footer: {
                Text("Reads Claude Code's own login from your macOS keychain (you'll be asked to allow access once) and shows Anthropic's real utilization — the same numbers as /status. When off, the widget uses only local logs. Note: third-party use of the login is discouraged by Anthropic's terms.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Data") {
                Button("Re-prompt for ~/.claude access") {
                    HomeAccessPrompter.shared.prompt()
                }
            }
        }
        .formStyle(.grouped)
        .alert("Menu bar setting saved", isPresented: $showRelaunchPrompt) {
            Button("Quit and reopen") { NSApplication.relaunchApp() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Menu bar mode setting saved. The Dock icon will remain visible — relaunching is only needed to attach (or detach) the menu-bar item this session.")
        }
    }

    private func limitField(_ binding: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            TextField("0", value: binding, format: .number)
                .frame(width: 70).multilineTextAlignment(.trailing)
            Text("M tok").foregroundStyle(.secondary)
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

