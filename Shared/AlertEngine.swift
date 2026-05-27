import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

enum AlertEngine {
    enum Kind: Equatable {
        case threshold(Double)              // 0.80 or 0.95
        case forecast(etaSeconds: Double)
    }
    struct Alert: Equatable {
        let kind: Kind
        let title: String
        let body: String
    }

    /// Inputs needed to decide; orchestrator builds these from snapshot + persisted state.
    struct State {
        var utilization: Double
        var resetsAt: Date?
        var lastThresholdFired: Double?     // 0.80 or 0.95 already fired for current window
        var forecastFiredAt: Date?          // already fired forecast for current window
        var burnTokensPerSec: Double
        var inferredLimitTokens: Int
        var currentTokens: Int
    }

    static func evaluate(prev: State, new: State, now: Date) -> [Alert] {
        var out: [Alert] = []

        let windowRolled = prev.resetsAt != new.resetsAt
        let armedThreshold = windowRolled ? nil : new.lastThresholdFired

        for threshold in [0.95, 0.80] {
            let alreadyFired = (armedThreshold ?? -1) >= threshold
            if !alreadyFired && new.utilization >= threshold {
                let pct = Int(threshold * 100)
                out.append(Alert(
                    kind: .threshold(threshold),
                    title: "Claude usage at \(pct)%",
                    body: "You've crossed \(pct)% of your inferred limit."
                ))
                break // only the highest crossed threshold per tick
            }
        }

        // Forecast: time to 100% at current burn rate.
        if new.burnTokensPerSec > 0,
           let resetsAt = new.resetsAt {
            let remainingTokens = max(0, new.inferredLimitTokens - new.currentTokens)
            let eta = Double(remainingTokens) / new.burnTokensPerSec
            let windowRemaining = resetsAt.timeIntervalSince(now)
            let didFireThisWindow = (prev.forecastFiredAt != nil) && !windowRolled
            if !didFireThisWindow && eta < windowRemaining - 1800 && eta > 0 {
                let minutes = Int(eta / 60)
                out.append(Alert(
                    kind: .forecast(etaSeconds: eta),
                    title: "Pace will hit limit",
                    body: "At current rate you'll hit 100% in ~\(minutes) min."
                ))
            }
        }
        return out
    }

    #if canImport(UserNotifications)
    static func deliver(_ alerts: [Alert]) {
        let center = UNUserNotificationCenter.current()
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            let req = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
            center.add(req, withCompletionHandler: nil)
        }
    }
    #endif
}
