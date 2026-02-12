import Foundation

final class CredentialManager {
    static let shared = CredentialManager()
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let tokenEndpoint = "https://platform.claude.com/v1/oauth/token"

    private var cachedCredential: OAuthCredential?
    private var _isLoggedOut = false

    private init() {}

    // MARK: - Read from ~/.claude/.credentials.json

    func readCredentialsFromDisk() -> OAuthCredential? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let credPath = home.appendingPathComponent(".claude/.credentials.json")

        guard let data = try? Data(contentsOf: credPath),
              let creds = try? JSONDecoder().decode(CredentialsFile.self, from: data) else {
            return nil
        }
        cachedCredential = creds.claudeAiOauth
        return creds.claudeAiOauth
    }

    // MARK: - Token Access

    func getToken() -> String? {
        cachedCredential?.accessToken ?? readCredentialsFromDisk()?.accessToken
    }

    var isTokenExpired: Bool {
        guard let cred = cachedCredential ?? readCredentialsFromDisk(),
              let expiresAt = cred.expiresAt else { return false }
        return Date().timeIntervalSince1970 * 1000 > expiresAt
    }

    // MARK: - Logout / Login

    var isLoggedOut: Bool { _isLoggedOut }

    func logout() {
        cachedCredential = nil
        _isLoggedOut = true
    }

    func clearLoggedOutFlag() {
        _isLoggedOut = false
    }

    // MARK: - Token Refresh

    func refreshTokenIfNeeded() async -> String? {
        let cred: OAuthCredential
        if let cached = cachedCredential {
            cred = cached
        } else if let fromDisk = readCredentialsFromDisk() {
            cred = fromDisk
        } else {
            return nil
        }

        // Not expired - use as-is
        guard let expiresAt = cred.expiresAt,
              Date().timeIntervalSince1970 * 1000 > expiresAt else {
            return cred.accessToken
        }

        // Try refresh
        guard let refreshToken = cred.refreshToken else {
            return cred.accessToken
        }

        guard let url = URL(string: Self.tokenEndpoint) else {
            return cred.accessToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(Self.clientID)"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                NSLog("[CredentialManager] refresh failed: status=\((response as? HTTPURLResponse)?.statusCode ?? -1)")
                // Still return current token - API might accept it
                return cred.accessToken
            }

            struct TokenResponse: Codable {
                let access_token: String
                let refresh_token: String?
                let expires_in: Double?
            }

            let tokenResp = try JSONDecoder().decode(TokenResponse.self, from: data)
            cachedCredential = OAuthCredential(
                accessToken: tokenResp.access_token,
                refreshToken: tokenResp.refresh_token ?? refreshToken,
                expiresAt: tokenResp.expires_in.map { Date().timeIntervalSince1970 * 1000 + $0 * 1000 }
            )
            return tokenResp.access_token
        } catch {
            NSLog("[CredentialManager] refresh error: \(error)")
            return cred.accessToken
        }
    }
}
