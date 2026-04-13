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
    var llmEndpoint: String = ""
    var llmModel: String = "gpt-4o-mini"
    var codeownerContext: String = ""
    var pollingIntervalSeconds: Int = 300
    var hideDraftPRs: Bool = true
    var notificationsEnabled: Bool = true
    var keepUnreviewedPriorityAfterMerge: Bool = true

    static let `default` = AppSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        githubUsername = try container.decodeIfPresent(String.self, forKey: .githubUsername) ?? ""
        repos = try container.decodeIfPresent([RepoConfig].self, forKey: .repos) ?? []
        buildkiteOrgSlug = try container.decodeIfPresent(String.self, forKey: .buildkiteOrgSlug) ?? ""
        llmEndpoint = try container.decodeIfPresent(String.self, forKey: .llmEndpoint) ?? ""
        llmModel = try container.decodeIfPresent(String.self, forKey: .llmModel) ?? "gpt-4o-mini"
        codeownerContext = try container.decodeIfPresent(String.self, forKey: .codeownerContext) ?? ""
        pollingIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .pollingIntervalSeconds) ?? 300
        hideDraftPRs = try container.decodeIfPresent(Bool.self, forKey: .hideDraftPRs) ?? true
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        keepUnreviewedPriorityAfterMerge = try container.decodeIfPresent(Bool.self, forKey: .keepUnreviewedPriorityAfterMerge) ?? true
    }
}
