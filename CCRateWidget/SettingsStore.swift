import Foundation
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var oauthEnabled: Bool {
        didSet { defaults.set(oauthEnabled, forKey: "oauthEnabled") }
    }
    @Published var menuBarEnabled: Bool {
        didSet { defaults.set(menuBarEnabled, forKey: "menuBarEnabled") }
    }

    /// Global ⌥⌘U to summon the HUD. Defaults on — it's the app's primary glance
    /// surface now that the widget is gone.
    @Published var hotkeyEnabled: Bool {
        didSet { defaults.set(hotkeyEnabled, forKey: "hotkeyEnabled") }
    }

    /// Optional user-entered token caps, in MILLIONS of tokens. 0 = unset (no percentage).
    @Published var fiveHourLimitMillions: Double {
        didSet { defaults.set(fiveHourLimitMillions, forKey: Self.fiveHourLimitKey) }
    }
    @Published var weeklyLimitMillions: Double {
        didSet { defaults.set(weeklyLimitMillions, forKey: Self.weeklyLimitKey) }
    }

    static let fiveHourLimitKey = "fiveHourLimitMillions"
    static let weeklyLimitKey   = "weeklyLimitMillions"

    private let defaults: UserDefaults
    private init() {
        _ = LocalStore.settingsMigrated   // must run before the first read, not after
        self.defaults = UserDefaults.standard
        self.oauthEnabled = defaults.bool(forKey: "oauthEnabled")              // default false
        self.menuBarEnabled = defaults.bool(forKey: "menuBarEnabled")          // default false
        // Opt-out rather than opt-in: registering an unused hotkey costs nothing, and
        // an unusable default would leave the app with no glance surface at all.
        self.hotkeyEnabled = defaults.object(forKey: "hotkeyEnabled") as? Bool ?? true
        self.fiveHourLimitMillions = defaults.double(forKey: Self.fiveHourLimitKey)  // default 0
        self.weeklyLimitMillions = defaults.double(forKey: Self.weeklyLimitKey)      // default 0
    }
}
