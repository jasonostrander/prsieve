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
    var notificationsEnabled: Bool = true

    static let `default` = AppSettings()
}
