import Foundation
import CryptoKit

final class CredentialManager {
    static let shared = CredentialManager()

    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authURL = "https://claude.ai/oauth/authorize"
    static let tokenExchangeURL = "https://console.anthropic.com/v1/oauth/token"
    static let tokenRefreshURL = "https://platform.claude.com/v1/oauth/token"
    static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    static let scopes = "org:create_api_key user:profile user:inference"

    private init() {
        cleanupKeychain()
    }

    // MARK: - File-based Storage

    private var storageDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Library/Application Support/ClaudeRateWidget")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var credentialFile: URL { storageDir.appendingPathComponent("credentials.json") }
    private var cachedDataFile: URL { storageDir.appendingPathComponent("cached_rate_data.json") }

    private struct StoredCredentials: Codable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Double?
    }

    private func readStoredCredentials() -> StoredCredentials? {
        guard let data = try? Data(contentsOf: credentialFile) else { return nil }
        return try? JSONDecoder().decode(StoredCredentials.self, from: data)
    }

    private func writeStoredCredentials(_ creds: StoredCredentials) {
        if let data = try? JSONEncoder().encode(creds) {
            try? data.write(to: credentialFile, options: .atomic)
        }
    }

    func saveTokens(accessToken: String, refreshToken: String?, expiresAt: Double?) {
        writeStoredCredentials(StoredCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        ))
    }

    func getAccessToken() -> String? { readStoredCredentials()?.accessToken }

    var hasCredentials: Bool { readStoredCredentials() != nil }

    func clearCredentials() {
        try? FileManager.default.removeItem(at: credentialFile)
        // Also clean up old keychain items if they exist
        cleanupKeychain()
    }

    // MARK: - Cached Rate Data (for widget)

    func saveCachedRateData(_ data: RateData) {
        let cached = CachedRateData(
            sessionUtilization: data.session.utilization,
            sessionResetsAt: data.session.resetsAt?.timeIntervalSince1970,
            weeklyUtilization: data.weekly.utilization,
            weeklyResetsAt: data.weekly.resetsAt?.timeIntervalSince1970,
            weeklySonnetUtilization: data.weeklySonnet.utilization,
            weeklySonnetResetsAt: data.weeklySonnet.resetsAt?.timeIntervalSince1970,
            overageIsEnabled: data.overage.isEnabled,
            overageUtilization: data.overage.utilization,
            overageSpent: data.overage.spent,
            overageLimit: data.overage.limit,
            fetchedAt: data.fetchedAt.timeIntervalSince1970,
            status: data.status.rawValue
        )
        if let json = try? JSONEncoder().encode(cached) {
            try? json.write(to: cachedDataFile, options: .atomic)
        }
    }

    func loadCachedRateData() -> RateData? {
        guard let data = try? Data(contentsOf: cachedDataFile),
              let cached = try? JSONDecoder().decode(CachedRateData.self, from: data) else {
            return nil
        }
        return cached.toRateData()
    }

    // MARK: - Token Refresh

    func refreshTokenIfNeeded() async -> String? {
        guard let creds = readStoredCredentials() else { return nil }

        // Check if expired
        if let expiresAt = creds.expiresAt {
            let now = Date().timeIntervalSince1970 * 1000
            guard now > expiresAt else { return creds.accessToken }
        } else {
            return creds.accessToken
        }

        // Try refresh
        guard let refreshToken = creds.refreshToken,
              let url = URL(string: Self.tokenRefreshURL) else {
            return creds.accessToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(Self.clientID)".data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return creds.accessToken
            }
            let tokenResp = try JSONDecoder().decode(TokenResponse.self, from: data)
            let newExpiresAt = tokenResp.expires_in.map { Date().timeIntervalSince1970 * 1000 + $0 * 1000 }
            saveTokens(
                accessToken: tokenResp.access_token,
                refreshToken: tokenResp.refresh_token ?? refreshToken,
                expiresAt: newExpiresAt
            )
            return tokenResp.access_token
        } catch {
            return creds.accessToken
        }
    }

    // MARK: - OAuth Token Exchange

    func exchangeCodeForTokens(code: String, codeVerifier: String, state: String) async -> Bool {
        guard let url = URL(string: Self.tokenExchangeURL) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": Self.clientID,
            "code": code,
            "redirect_uri": Self.redirectURI,
            "code_verifier": codeVerifier,
            "state": state,
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }
            let tokenResp = try JSONDecoder().decode(TokenResponse.self, from: data)
            let expiresAt = tokenResp.expires_in.map { Date().timeIntervalSince1970 * 1000 + $0 * 1000 }
            saveTokens(
                accessToken: tokenResp.access_token,
                refreshToken: tokenResp.refresh_token,
                expiresAt: expiresAt
            )
            return true
        } catch {
            return false
        }
    }

    // MARK: - PKCE

    static func generatePKCE() -> (verifier: String, challenge: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let challengeData = Data(SHA256.hash(data: Data(verifier.utf8)))
        let challenge = challengeData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return (verifier, challenge)
    }

    // MARK: - Keychain Cleanup

    private func cleanupKeychain() {
        // Remove all generic password items for our service
        for service in ["com.dkkang.cc-rate-widget", "cc-rate-widget", "ClaudeRateWidget"] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
            ]
            SecItemDelete(query as CFDictionary)
        }
        // Also remove any items matching our bundle ID prefix
        let bundleQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrLabel as String: "com.dkkang.cc-rate-widget",
        ]
        SecItemDelete(bundleQuery as CFDictionary)
    }
}

// MARK: - Token Response

struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double?
}

// MARK: - Cached Rate Data

struct CachedRateData: Codable {
    let sessionUtilization: Double
    let sessionResetsAt: Double?
    let weeklyUtilization: Double
    let weeklyResetsAt: Double?
    let weeklySonnetUtilization: Double
    let weeklySonnetResetsAt: Double?
    let overageIsEnabled: Bool
    let overageUtilization: Double
    let overageSpent: Double
    let overageLimit: Double
    let fetchedAt: Double
    let status: String

    func toRateData() -> RateData {
        RateData(
            session: CategoryData(utilization: sessionUtilization, resetsAt: sessionResetsAt.map { Date(timeIntervalSince1970: $0) }),
            weekly: CategoryData(utilization: weeklyUtilization, resetsAt: weeklyResetsAt.map { Date(timeIntervalSince1970: $0) }),
            weeklySonnet: CategoryData(utilization: weeklySonnetUtilization, resetsAt: weeklySonnetResetsAt.map { Date(timeIntervalSince1970: $0) }),
            overage: OverageData(isEnabled: overageIsEnabled, utilization: overageUtilization, spent: overageSpent, limit: overageLimit),
            fetchedAt: Date(timeIntervalSince1970: fetchedAt),
            status: OverallStatus(rawValue: status) ?? .unknown
        )
    }
}
