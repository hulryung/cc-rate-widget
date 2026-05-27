import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store = SettingsStore.shared
    @State private var showRelaunchPrompt = false

    var body: some View {
        Form {
            Section("Plan tier") {
                Picker("Plan", selection: $store.manualPlanTier) {
                    Text("Auto (P90)").tag("auto")
                    Text("Pro").tag("pro")
                    Text("Max5").tag("max5")
                    Text("Max20").tag("max20")
                }
                .pickerStyle(.menu)
                .onChange(of: store.manualPlanTier) { _, new in
                    persistManualTier(new)
                }
                Text("Choose the tier that matches your subscription, or leave on Auto to let the widget estimate from your usage history.")
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
                Text("Off by default. Anthropic's terms discourage third-party OAuth use; enabling places that responsibility on you.")
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
            Text("Menu bar mode setting saved. Relaunching attaches (or detaches) the menu-bar item this session.")
        }
    }

    private func persistManualTier(_ raw: String) {
        var limits = (try? AppGroupStore.shared.readLimits())
            ?? InferredLimits()
        switch raw {
        case "pro":   limits.manualPlanTier = .pro
        case "max5":  limits.manualPlanTier = .max5
        case "max20": limits.manualPlanTier = .max20
        default:      limits.manualPlanTier = nil
        }
        try? AppGroupStore.shared.writeLimits(limits)
        AggregationCoordinator.shared.runOnce()
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

