import SwiftUI

struct OAuthLoginButton: View {
    let onSuccess: () -> Void
    let onError: (String) -> Void

    @State private var showCodeEntry = false
    @State private var codeText = ""
    @State private var isExchanging = false
    @State private var codeVerifier = ""
    @State private var oauthState = ""

    var body: some View {
        VStack(spacing: 8) {
            if showCodeEntry {
                codeEntryView
            } else {
                Button(action: startLogin) {
                    Text("Login")
                        .font(.caption.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(.orange, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var codeEntryView: some View {
        VStack(spacing: 8) {
            Text("Paste the URL or code from the browser")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Code or URL", text: $codeText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(maxWidth: 280)
                    .onSubmit { submitCode() }
                if isExchanging {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Button("Submit") { submitCode() }
                        .font(.caption.bold())
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                    Button("Cancel") {
                        showCodeEntry = false
                        codeText = ""
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func startLogin() {
        let pkce = CredentialManager.generatePKCE()
        let state = UUID().uuidString
        codeVerifier = pkce.verifier
        oauthState = state

        var components = URLComponents(string: CredentialManager.authURL)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: CredentialManager.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: CredentialManager.redirectURI),
            URLQueryItem(name: "scope", value: CredentialManager.scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
            showCodeEntry = true
        }
    }

    private func submitCode() {
        var input = codeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        // Remove URL fragment (#...) if present
        if let hashIdx = input.firstIndex(of: "#") {
            input = String(input[..<hashIdx])
        }

        // Extract code from URL or use raw code
        let code: String
        if input.contains("code="), let url = URLComponents(string: input),
           let c = url.queryItems?.first(where: { $0.name == "code" })?.value {
            code = c
        } else {
            code = input
        }

        NSLog("[OAuth] submitting code: \(code.prefix(10))... verifier: \(codeVerifier.prefix(10))...")

        isExchanging = true
        Task {
            let success = await CredentialManager.shared.exchangeCodeForTokens(
                code: code, codeVerifier: codeVerifier, state: oauthState
            )
            await MainActor.run {
                isExchanging = false
                if success {
                    showCodeEntry = false
                    codeText = ""
                    onSuccess()
                } else {
                    onError("Token exchange failed. Try again.")
                }
            }
        }
    }
}
