import SwiftUI

struct SettingsView: View {
    @ObservedObject var store = SettingsStore.shared

    /// Read on each appearance rather than observed: Settings is opened, glanced at and
    /// closed, and a file that changes every few seconds isn't worth a watcher.
    private var statusLineActive: Bool {
        StatusLineUsage.read(from: LocalStore.shared.container) != nil
    }

    var body: some View {
        Form {
            Section {
                Text("Claude Rate Monitor reports the tokens and cost recorded in your local Claude Code logs.")
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
                // No toggle for the menu bar itself: it is the app's only permanent
                // surface, so hiding it would leave nothing to click.
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
                // Live rather than instructional: whether the file is arriving is the one
                // thing you cannot tell by reading your own config.
                if statusLineActive {
                    Label("Your status line is publishing Anthropic's percentages.",
                          systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Not set up — the README shows the two lines to add.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Official usage")
            } footer: {
                Text("Claude Code hands its status-line script the same percentages /status prints. Have that script write them out and this app reads them — no login, no keychain, no network call of its own.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Read the keychain instead", isOn: $store.oauthEnabled)
                    .onChange(of: store.oauthEnabled) { _, _ in AggregationCoordinator.shared.runOnce() }

                // Promoted out of the footer: as gray body text at the end of four
                // sentences, the one sentence with real consequences went unread.
                Label("Anthropic's terms discourage third-party use of this login.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } footer: {
                Text("The old path, for when no status line is publishing. It borrows Claude Code's login from your keychain and calls an endpoint Anthropic doesn't document. macOS gates that keychain item on a partition list, so granting one program access can lock the other out — expect repeat prompts. Used only when status-line data is missing or over an hour old.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Data") {
                Button("Re-prompt for ~/.claude access") {
                    HomeAccessPrompter.shared.prompt()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func limitField(_ binding: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            TextField("0", value: binding, format: .number)
                .frame(width: 70).multilineTextAlignment(.trailing)
            Text("M tok").foregroundStyle(.secondary)
        }
    }
}
