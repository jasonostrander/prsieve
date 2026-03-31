import Foundation

actor PersistenceService {
    private let appSupportDir: URL
    private let settingsURL: URL
    private let pullRequestsURL: URL
    private let tokensURL: URL
    private let codeownersCacheDir: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appSupportDir = appSupport.appendingPathComponent("PRSieve", isDirectory: true)
        settingsURL = appSupportDir.appendingPathComponent("settings.json")
        pullRequestsURL = appSupportDir.appendingPathComponent("pull_requests.json")
        tokensURL = appSupportDir.appendingPathComponent(".tokens.json")
        codeownersCacheDir = appSupportDir.appendingPathComponent("codeowners_cache", isDirectory: true)

        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codeownersCacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Settings

    func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? decoder.decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func saveSettings(_ settings: AppSettings) throws {
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL, options: .atomic)
    }

    // MARK: - Tokens (file-based, avoids Keychain prompts for unsigned apps)

    private func loadTokens() -> [String: String] {
        guard let data = try? Data(contentsOf: tokensURL),
              let tokens = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return tokens
    }

    private func saveTokens(_ tokens: [String: String]) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        try? data.write(to: tokensURL, options: .atomic)
        // Restrict file permissions to owner-only
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: tokensURL.path
        )
    }

    func loadToken(forKey key: String) -> String? {
        loadTokens()[key]
    }

    func saveToken(_ token: String, forKey key: String) {
        var tokens = loadTokens()
        tokens[key] = token
        saveTokens(tokens)
    }

    // MARK: - Pull Requests

    func loadPullRequests() -> [PullRequest] {
        guard let data = try? Data(contentsOf: pullRequestsURL),
              let prs = try? decoder.decode([PullRequest].self, from: data) else {
            return []
        }
        return prs
    }

    func savePullRequests(_ prs: [PullRequest]) throws {
        let data = try encoder.encode(prs)
        try data.write(to: pullRequestsURL, options: .atomic)
    }

    // MARK: - CODEOWNERS Cache

    func loadCodeowners(forRepo repo: String) -> String? {
        let filename = repo.replacingOccurrences(of: "/", with: "_") + ".txt"
        let url = codeownersCacheDir.appendingPathComponent(filename)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func saveCodeowners(_ content: String, forRepo repo: String) throws {
        let filename = repo.replacingOccurrences(of: "/", with: "_") + ".txt"
        let url = codeownersCacheDir.appendingPathComponent(filename)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
