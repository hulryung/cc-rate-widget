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
                Text("Usage limits")
            } footer: {
                Text("Set your plan's limits to see a percentage. 0 shows absolute usage only.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .onChange(of: store.fiveHourLimitMillions) { _, _ in AggregationCoordinator.shared.runOnce() }
            .onChange(of: store.weeklyLimitMillions) { _, _ in AggregationCoordinator.shared.runOnce() }

            Section {
                Toggle("Show in menu bar", isOn: $store.menuBarEnabled)
                    .onChange(of: store.menuBarEnabled) { _, on in
                        if on { MenuBarMode.shared.install() } else { MenuBarMode.shared.remove() }
                    }
                Toggle("Global shortcut (⌥⌘U)", isOn: $store.hotkeyEnabled)
                    .onChange(of: store.hotkeyEnabled) { _, on in
                        if on { UsageHUD.shared.registerHotKey() } else { UsageHUD.shared.unregisterHotKey() }
                    }
            } header: {
                Text("Quick access")
            } footer: {
                Text("The menu bar shows your weekly percentage; click it for the full summary. The shortcut shows the same summary anywhere, including over full-screen apps, and dismisses itself.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show official usage %", isOn: $store.oauthEnabled)
                    .onChange(of: store.oauthEnabled) { _, _ in AggregationCoordinator.shared.runOnce() }

                // Promoted out of the footer: as gray body text at the end of four
                // sentences, the one sentence with real consequences went unread.
                Label("Anthropic's terms discourage third-party use of this login.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } header: {
                Text("Official usage")
            } footer: {
                Text("Reads Claude Code's login from your keychain to show the same percentages as /status. When off, only local logs are used.")
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

