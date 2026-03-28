import Foundation
import Security

actor PersistenceService {
    private let appSupportDir: URL
    private let settingsURL: URL
    private let pullRequestsURL: URL
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

    // MARK: - Keychain (tokens)

    func loadToken(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.jasonostrander.prsieve",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveToken(_ token: String, forKey key: String) {
        let data = token.data(using: .utf8)!

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.jasonostrander.prsieve",
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.jasonostrander.prsieve",
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
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
