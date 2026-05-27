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
    @Published var manualPlanTier: String {
        didSet { defaults.set(manualPlanTier, forKey: "manualPlanTier") }
    }

    private let defaults: UserDefaults
    private init() {
        self.defaults = UserDefaults(suiteName: "group.com.dkkang.cc-rate-widget") ?? .standard
        self.oauthEnabled = defaults.bool(forKey: "oauthEnabled")              // default false
        self.menuBarEnabled = defaults.bool(forKey: "menuBarEnabled")          // default false
        self.manualPlanTier = defaults.string(forKey: "manualPlanTier") ?? "auto"
    }
}
