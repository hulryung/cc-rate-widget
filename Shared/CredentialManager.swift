import Foundation
import CryptoKit

final class CredentialManager {
    static let shared = CredentialManager()

    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authURL = "https://claude.ai/oauth/authorize"
    static let tokenExchangeURL = "https://platform.claude.com/v1/oauth/token"
    static let tokenRefreshURL = "https://platform.claude.com/v1/oauth/token"
    static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    static let scopes = "org:create_api_key user:profile user:inference"

    private init() {}

    // MARK: - Shared Storage via App Group UserDefaults
    private static let appGroupID = "group.com.dkkang.cc-rate-widget"
    private let defaults = UserDefaults(suiteName: appGroupID)!

    // MARK: - Credential Storage

    private struct StoredCredentials: Codable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Double?
    }

    private func readStoredCredentials() -> StoredCredentials? {
        guard let data = defaults.data(forKey: "credentials"),
              let creds = try? JSONDecoder().decode(StoredCredentials.self, from: data) else {
            return nil
        }
        return creds
    }

    private func writeStoredCredentials(_ creds: StoredCredentials) {
        if let data = try? JSONEncoder().encode(creds) {
            defaults.set(data, forKey: "credentials")
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
        defaults.removeObject(forKey: "credentials")
        defaults.removeObject(forKey: "cached_rate_data")
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
                let httpResp = response as? HTTPURLResponse
                NSLog("[OAuth] Token refresh failed: \(httpResp?.statusCode ?? -1) \(String(data: data, encoding: .utf8) ?? "")")
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
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            guard httpResponse.statusCode == 200 else {
                NSLog("[OAuth] Token exchange failed: \(httpResponse.statusCode) \(String(data: data, encoding: .utf8) ?? "")")
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
            NSLog("[OAuth] Token exchange error: \(error)")
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
}

// MARK: - Token Response

struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double?
}

