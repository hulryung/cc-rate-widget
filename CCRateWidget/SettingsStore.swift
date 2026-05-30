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
        self.defaults = UserDefaults(suiteName: "group.com.dkkang.cc-rate-widget") ?? .standard
        self.oauthEnabled = defaults.bool(forKey: "oauthEnabled")              // default false
        self.menuBarEnabled = defaults.bool(forKey: "menuBarEnabled")          // default false
        self.fiveHourLimitMillions = defaults.double(forKey: Self.fiveHourLimitKey)  // default 0
        self.weeklyLimitMillions = defaults.double(forKey: Self.weeklyLimitKey)      // default 0
    }
}
