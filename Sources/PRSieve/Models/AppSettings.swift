import Foundation

struct RepoConfig: Codable, Sendable, Identifiable, Hashable {
    var id: String { repo }
    let repo: String  // "owner/repo"
    var buildkitePipeline: String?  // optional override for pipeline slug
}

struct AppSettings: Codable, Sendable, Equatable {
    var githubUsername: String = ""
    var repos: [RepoConfig] = []
    var buildkiteOrgSlug: String = ""
    var codeownerContext: String = ""
    var pollingIntervalSeconds: Int = 300
    var hideDraftPRs: Bool = true
    var notificationsEnabled: Bool = true
    var keepUnreviewedPriorityAfterMerge: Bool = true
    var ignoredCIChecks: [String] = ["danger/danger"]
    var launchAtLogin: Bool = false

    static let `default` = AppSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        githubUsername = try container.decodeIfPresent(String.self, forKey: .githubUsername) ?? ""
        repos = try container.decodeIfPresent([RepoConfig].self, forKey: .repos) ?? []
        buildkiteOrgSlug = try container.decodeIfPresent(String.self, forKey: .buildkiteOrgSlug) ?? ""
        codeownerContext = try container.decodeIfPresent(String.self, forKey: .codeownerContext) ?? ""
        pollingIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .pollingIntervalSeconds) ?? 300
        hideDraftPRs = try container.decodeIfPresent(Bool.self, forKey: .hideDraftPRs) ?? true
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        keepUnreviewedPriorityAfterMerge = try container.decodeIfPresent(Bool.self, forKey: .keepUnreviewedPriorityAfterMerge) ?? true
        ignoredCIChecks = try container.decodeIfPresent([String].self, forKey: .ignoredCIChecks) ?? ["danger/danger"]
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }
}
