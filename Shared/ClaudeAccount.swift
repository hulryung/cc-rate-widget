import Foundation

/// The signed-in Claude account, so the numbers on screen say whose they are.
///
/// Claude Code records it in `~/.claude.json` under `oauthAccount`. That is a plain file
/// read: nothing to spawn, no PATH to guess at from a GUI app that never saw a login shell,
/// and nothing the Keychain gates. `claude auth status --json` reports the same address but
/// costs a process launch on a five-minute tick.
///
/// The file is well over 100 KB and changes constantly, so the result is cached against its
/// modification date rather than re-parsed on every refresh.
enum ClaudeAccount {
    private static var cached: (email: String?, mtime: Date)?
    private static let lock = NSLock()

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }

    /// nil when Claude Code has never signed in, or the file is gone or unreadable.
    static func email(at url: URL? = nil) -> String? {
        let url = url ?? configURL
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? nil

        lock.lock()
        defer { lock.unlock() }
        if let cached, let mtime, cached.mtime == mtime { return cached.email }

        let parsed = (try? Data(contentsOf: url)).flatMap { parse($0) }
        if let mtime { cached = (parsed, mtime) }
        return parsed
    }

    /// Pure half, so the shape can be tested without a home directory.
    static func parse(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = obj["oauthAccount"] as? [String: Any],
              let email = account["emailAddress"] as? String,
              !email.isEmpty else { return nil }
        return email
    }
}
