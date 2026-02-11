import Foundation

final class CredentialManager {
    static let shared = CredentialManager()
    static let appGroupID = "XGJ87M8ZZR.com.dkkang.cc-rate-widget"
    private static let tokenKey = "oauth_access_token"
    private static let expiresAtKey = "oauth_expires_at"
    private static let refreshTokenKey = "oauth_refresh_token"
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let tokenEndpoint = "https://platform.claude.com/v1/oauth/token"

    private init() {}

    // MARK: - Read from ~/.claude/.credentials.json (host app only)

    func readCredentialsFromDisk() -> OAuthCredential? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let credPath = home.appendingPathComponent(".claude/.credentials.json")

        guard let data = try? Data(contentsOf: credPath),
              let creds = try? JSONDecoder().decode(CredentialsFile.self, from: data) else {
            return nil
        }
        return creds.claudeAiOauth
    }

    // MARK: - App Group UserDefaults

    private var groupDefaults: UserDefaults? {
        UserDefaults(suiteName: Self.appGroupID)
    }

    func syncToAppGroup(_ credential: OAuthCredential) {
        guard let defaults = groupDefaults else { return }
        defaults.set(credential.accessToken, forKey: Self.tokenKey)
        if let expiresAt = credential.expiresAt {
            defaults.set(expiresAt, forKey: Self.expiresAtKey)
        }
        if let refreshToken = credential.refreshToken {
            defaults.set(refreshToken, forKey: Self.refreshTokenKey)
        }
        defaults.synchronize()
    }

    func getToken() -> String? {
        groupDefaults?.string(forKey: Self.tokenKey)
    }

    func getExpiresAt() -> Double? {
        let val = groupDefaults?.double(forKey: Self.expiresAtKey)
        return val == 0 ? nil : val
    }

    func getRefreshToken() -> String? {
        groupDefaults?.string(forKey: Self.refreshTokenKey)
    }

    var isTokenExpired: Bool {
        guard let expiresAt = getExpiresAt() else { return false }
        return Date().timeIntervalSince1970 * 1000 > expiresAt
    }

    // MARK: - Token Refresh

    func refreshTokenIfNeeded() async -> String? {
        guard let currentToken = getToken() else { return nil }
        guard isTokenExpired else { return currentToken }
        guard let refreshToken = getRefreshToken() else { return currentToken }

        guard let url = URL(string: Self.tokenEndpoint) else { return currentToken }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(Self.clientID)"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return currentToken
            }

            struct TokenResponse: Codable {
                let access_token: String
                let refresh_token: String?
                let expires_in: Double?
            }

            let tokenResp = try JSONDecoder().decode(TokenResponse.self, from: data)
            let expiresAt = tokenResp.expires_in.map { Date().timeIntervalSince1970 * 1000 + $0 * 1000 }

            let newCred = OAuthCredential(
                accessToken: tokenResp.access_token,
                refreshToken: tokenResp.refresh_token ?? refreshToken,
                expiresAt: expiresAt
            )
            syncToAppGroup(newCred)
            return tokenResp.access_token
        } catch {
            return currentToken
        }
    }
}
