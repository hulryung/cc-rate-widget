import AppKit

final class HomeAccessPrompter {
    static let shared = HomeAccessPrompter()
    private init() {}

    /// Open NSOpenPanel pinned to ~/.claude/projects to trigger a TCC prompt.
    /// User selects the folder; we do not need to retain a security-scoped bookmark
    /// because the main app runs unsandboxed (Task 2). The panel surface itself
    /// is what nudges TCC to prompt for home-folder access.
    func prompt() {
        let panel = NSOpenPanel()
        panel.message = "Select your ~/.claude/projects folder to allow Claude Rate Widget to read usage data."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        let home = FileManager.default.homeDirectoryForCurrentUser
        panel.directoryURL = home.appendingPathComponent(".claude/projects")
        panel.showsHiddenFiles = true
        panel.begin { _ in
            MainActor.assumeIsolated {
                AggregationCoordinator.shared.runOnce()
            }
        }
    }
}
