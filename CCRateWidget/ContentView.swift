import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var rateData: RateData?
    @State private var userInfo: UserInfo?
    @State private var isLoading = false
    @State private var loginError: String?
    @State private var credentialVersion = 0  // bump to force re-check

    private var isLoggedIn: Bool {
        _ = credentialVersion  // observe changes
        return CredentialManager.shared.hasCredentials
    }

    var body: some View {
        ZStack {
            Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 20) {
                header
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                        .tint(.white)
                } else if !isLoggedIn {
                    loginPromptView
                } else if let data = rateData, data.status == .unauthorized {
                    sessionExpiredView
                } else if let data = rateData, data.status == .error {
                    errorView
                } else if let data = rateData {
                    rateContent(data)
                }
                Spacer()
                footer
            }
            .padding(24)
        }
        .task { await loadData() }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("Claude Rate Widget")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Spacer()
            if isLoggedIn {
                Button(action: logout) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Logout")
            }
            Button(action: { Task { await loadData() } }) {
                Image(systemName: "arrow.clockwise")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh")
        }
    }

    private func rateContent(_ data: RateData) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                statusBadge(data.status)
                if let label = userInfo?.displayLabel {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            rateRow(label: "Session (5h)", data: data.session)
            rateRow(label: "Weekly", data: data.weekly)
            rateRow(label: "Weekly Sonnet", data: data.weeklySonnet)
            if data.overage.isEnabled {
                overageRow(data.overage)
            }
            Text("Updated \(data.fetchedAt.formatted(.relative(presentation: .named)))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func statusBadge(_ status: OverallStatus) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 8, height: 8)
            Text(status.label)
                .font(.caption.bold())
                .foregroundStyle(statusColor(status))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(statusColor(status).opacity(0.15), in: Capsule())
    }

    private func rateRow(label: String, data: CategoryData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(data.utilization * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
            }
            ProgressView(value: min(data.utilization, 1.0))
                .tint(barColor(data.utilization))
                .scaleEffect(y: 1.5)
            if let reset = data.resetsAt {
                Text("Resets \(reset.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func overageRow(_ data: OverageData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Overage")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("$\(String(format: "%.2f", data.spent)) / $\(String(format: "%.2f", data.limit))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
            }
            ProgressView(value: min(data.utilization, 1.0))
                .tint(barColor(data.utilization))
                .scaleEffect(y: 1.5)
        }
    }

    private var loginPromptView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Not Logged In")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Log in with your Claude account\nto view rate limits.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let loginError {
                Text(loginError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            OAuthLoginButton(
                onSuccess: { credentialVersion += 1; Task { await loadData() } },
                onError: { loginError = $0 }
            )
        }
        .padding()
    }

    private var sessionExpiredView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("Session Expired")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Your session has expired.\nPlease log in again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let loginError {
                Text(loginError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            OAuthLoginButton(
                onSuccess: { credentialVersion += 1; Task { await loadData() } },
                onError: { loginError = $0 }
            )
        }
        .padding()
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Failed to Fetch")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Could not reach the API. Check your connection.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: { Task { await loadData() } }) {
                Text("Retry")
                    .font(.caption.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.orange, in: Capsule())
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Button(action: {
                NSWorkspace.shared.open(URL(string: "https://github.com/hulryung/cc-rate-widget")!)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                    Text("GitHub")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Add widget via Widget Gallery")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func logout() {
        CredentialManager.shared.clearCredentials()
        rateData = nil
        credentialVersion += 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func loadData() async {
        guard isLoggedIn else { return }
        isLoading = true
        defer { isLoading = false }
        async let rateTask = RateFetcher.shared.fetchRateData()
        async let userTask = RateFetcher.shared.fetchUserInfo()
        let data = await rateTask
        userInfo = await userTask
        rateData = data
        if data.status != .error && data.status != .unauthorized {
            CredentialManager.shared.saveCachedRateData(data)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func statusColor(_ status: OverallStatus) -> Color {
        switch status {
        case .active: return .green
        case .warning: return .orange
        case .rateLimited: return .red
        case .unauthorized: return .red
        case .notLoggedIn: return .orange
        case .error: return .gray
        case .unknown: return .gray
        }
    }

    private func barColor(_ utilization: Double) -> Color {
        if utilization >= 1.0 { return .red }
        if utilization >= 0.8 { return .orange }
        return .green
    }
}
